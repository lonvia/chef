name "coastline"
description "Role applied to servers generating coastlines"

default_attributes(
  :accounts => {
    :users => {
      :jochen => {
        :status => :administrator
      },
      :coastline => {
        :status => :role,
        :members => [:jochen, :tomh]
      }
    }
  },
)

run_list(
  "recipe[coastline]"
)
