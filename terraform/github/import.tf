# Adopts the team you create by hand in Part A of docs/day02.md.
# Terraform reads it into state instead of trying to create a duplicate.
# Delete this file after the first successful apply.
import {
  to = github_team.this["platform-team"]
  id = "platform-team"
}
