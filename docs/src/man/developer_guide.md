# [Developer guide](@id developer_guide_man)

## Style guide
- Use `#!` for comments that are informative
  - This helps find code lines commented out in development.
  - Using the regexp `^(\s+)?# .+\n` seems to work well for finding commented out code lines.