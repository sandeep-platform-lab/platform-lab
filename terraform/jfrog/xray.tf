# Xray: scans what is stored and built. Policies say what's a violation and what to do about it;
# watches say where the policies apply.

# Builds must be indexed before a watch or `jf build-scan` can see them.
resource "xray_binary_manager_builds" "lab" {
  id             = "default"
  indexed_builds = ["lab-api"]
}

# ---------- Policies ----------

# CI gate: fail the build on HIGH/CRITICAL issues that have a fix. Matches the Trivy gate in CI.
resource "xray_security_policy" "build_gate" {
  name        = "lab-sec-build-gate"
  description = "Fail builds on fixable HIGH and CRITICAL vulnerabilities"
  type        = "security"

  rule {
    name     = "high-or-critical-with-fix"
    priority = 1

    criteria {
      min_severity          = "High"
      fix_version_dependant = true
    }

    actions {
      fail_build = true
      block_download {
        active    = false
        unscanned = false
      }
    }
  }
}

# Runtime: stop people and clusters from pulling the worst things out of Artifactory.
resource "xray_security_policy" "runtime" {
  name        = "lab-sec-runtime"
  description = "Block downloads of malicious packages and fixable CRITICAL vulnerabilities"
  type        = "security"

  rule {
    name     = "malicious-package"
    priority = 1

    criteria {
      malicious_package = true
    }

    actions {
      block_download {
        active    = true
        unscanned = false
      }
    }
  }

  rule {
    name     = "critical-with-fix"
    priority = 2

    criteria {
      min_severity          = "Critical"
      fix_version_dependant = true
    }

    actions {
      block_download {
        active    = true
        unscanned = false
      }
    }
  }
}

# Tracking: every HIGH+ issue, fixable or not, becomes a violation someone can see and triage.
# No blocking: blocking on things nobody can fix only teaches people to ignore the gate.
resource "xray_security_policy" "track" {
  name        = "lab-sec-track"
  description = "Record all HIGH and CRITICAL vulnerabilities for triage"
  type        = "security"

  rule {
    name     = "high-or-critical"
    priority = 1

    criteria {
      min_severity = "High"
    }

    actions {
      block_download {
        active    = false
        unscanned = false
      }
    }
  }
}

resource "xray_license_policy" "license" {
  name        = "lab-license"
  description = "Flag strong copyleft licences for legal review"
  type        = "license"

  rule {
    name     = "copyleft"
    priority = 1

    criteria {
      banned_licenses = ["AGPL-1.0", "AGPL-3.0", "GPL-2.0", "GPL-3.0"]
      allow_unknown   = true
    }

    actions {
      custom_severity = "High"
      block_download {
        active    = false
        unscanned = false
      }
    }
  }
}

# ---------- Watches ----------

resource "xray_watch" "dev_repos" {
  name        = "lab-dev-repos"
  description = "Dev, remote and evidence repos: track and flag, don't block"
  active      = true

  dynamic "watch_resource" {
    for_each = merge(
      { for k, v in local.local_repos : v => "local" if k != "docker_prod" },
      { for k, v in local.remote_repos : v => "remote" },
    )
    content {
      type       = "repository"
      bin_mgr_id = "default"
      name       = watch_resource.key
      repo_type  = watch_resource.value
    }
  }

  assigned_policy {
    name = xray_security_policy.track.name
    type = "security"
  }
  assigned_policy {
    name = xray_license_policy.license.name
    type = "license"
  }
}

resource "xray_watch" "prod_repo" {
  name        = "lab-prod-repo"
  description = "Prod repo: block what must never run"
  active      = true

  watch_resource {
    type       = "repository"
    bin_mgr_id = "default"
    name       = local.local_repos.docker_prod
    repo_type  = "local"
  }

  assigned_policy {
    name = xray_security_policy.runtime.name
    type = "security"
  }
  assigned_policy {
    name = xray_security_policy.track.name
    type = "security"
  }
}

resource "xray_watch" "builds" {
  name        = "lab-builds"
  description = "CI builds of lab-api: the gate used by jf build-scan"
  active      = true

  watch_resource {
    type       = "build"
    bin_mgr_id = "default"
    name       = "lab-api"
  }

  assigned_policy {
    name = xray_security_policy.build_gate.name
    type = "security"
  }
  assigned_policy {
    name = xray_security_policy.track.name
    type = "security"
  }
  assigned_policy {
    name = xray_license_policy.license.name
    type = "license"
  }

  depends_on = [xray_binary_manager_builds.lab]
}

resource "xray_ignore_rule" "base_image_cve" {
  notes           = "No fix in Debian yet; not reachable from lab-api. Re-check on expiry. Ticket: LAB-1"
  expiration_date = "2026-11-15"
  cves            = ["CVE-2026-97689"] # from Part B
  watches         = [xray_watch.builds.name]
}