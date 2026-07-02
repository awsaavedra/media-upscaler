## Summary
<!-- What this PR changes and why. Keep it to one focused feature or fix. -->

## Type
<!-- add / fix / doc / refactor / stabilize / edit -->

## Checklist
- [ ] Commit messages follow `#type, what; what` with no `Co-Authored-By` footer (see CONTRIBUTING.md)
- [ ] `./scripts/test.sh` fast suite passes
- [ ] `./scripts/test.sh --integration` run (required for changes to inference paths or quality thresholds)
- [ ] `bash -n scripts/*.sh` is clean
- [ ] Docs updated in the same commit as the code
- [ ] New numeric logic lives in Python, not shell (Rule 11)
- [ ] Exit-code contracts preserved (0 / 1 / 2 / 3)

## Related issues
