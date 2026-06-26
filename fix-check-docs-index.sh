#!/bin/bash
# Adding the new skills into README.md
sed -i 's/taskwarrior-plugin.*| 6 |/taskwarrior-plugin | 8 |/' README.md
sed -i 's/taskwarrior\\n6 skills/taskwarrior\\n8 skills/' docs/diagrams/plugin-relationships.d2
