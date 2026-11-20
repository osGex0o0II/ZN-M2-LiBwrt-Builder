[.[][]
  | select(.published_at != null and (.draft | not)
      and .tag_name != $current and (.tag_name | endswith("-" + $slug))
      and .prerelease == $preview)]
| sort_by(.published_at) | reverse | .[].tag_name
