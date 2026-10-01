# Protects the default branch: every change goes through a reviewed PR with green CI.
resource "github_repository_ruleset" "main" {
  name        = "main-protection"
  repository  = data.github_repository.lab.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # Break-glass: org admins may merge a PR without the approval (they still need a PR).
  # Needed in a one-person lab, since nobody can approve their own PR.
  bypass_actors {
    actor_id    = 1
    actor_type  = "OrganizationAdmin"
    bypass_mode = "pull_request"
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      required_approving_review_count   = 1
      require_code_owner_review         = true
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      required_check {
        context        = "build-test"
        integration_id = 15368 # GitHub Actions: only Actions can satisfy this check
      }
    }
  }
}
