# lib/config/navigation-back.jq — the screen Back returns to, for every
# screen but `secret` (navigation_secret_return owns that one). Input: the
# current nav object. A `focus` names the row Back lands on, so the cursor is
# restored there.

# The Profiles picker and the New host confirm sit above the top screen.
if   .screen == "profiles"
     then {screen:"top"}
elif .screen == "newhost"
     then {screen:"profiles"}
# The root editor and the users list return to the Users list / top screen.
elif .screen == "rooteditor"
     then {screen:"values",category:.category,field:"users",label:"users"}
elif .screen == "values" and .field == "users"
     then {screen:"top", focus:.category}
# A field picker or text editor returns to its category, on that field.
elif .screen == "values" or .screen == "text"
     then {screen:"category", category:.category, focus:.label}
# The Disks sub-editors return to the Disks category, on their row.
elif .screen == "swapedit"
     then {screen:"category", category:.category, focus:"Swap"}
elif .screen == "encryption"
     then {screen:"category", category:.category, focus:"Encryption"}
elif .screen == "impermanence"
     then {screen:"category", category:.category, focus:"Impermanence"}
# Pools: the disks of a pool → the pool → the pool list → the category.
elif .screen == "datapools" then {screen:"category", category:.category}
elif .screen == "pooledit"  then {screen:"datapools", category:.category}
elif .screen == "pooldisks"
     then {screen:"pooledit", category:.category,
           index:.index, kind:.kind}
elif .screen == "rootdisk" then {screen:"category", category:.category}
# Users: a user field → the user → the Users list.
elif .screen == "useredit"
     then {screen:"values", category:.category, field:"users", label:"users"}
elif .screen == "userfield"
     then {screen:"useredit", category:.category, user:.user}
# Packages: packages → their slot's categories → the category.
elif .screen == "pkgcat" then {screen:"category", category:.category}
elif .screen == "pkgs"
     then {screen:"pkgcat", category:.category, slot:.slot}
elif .screen == "pkgbrowse"
     then {screen:"pkgcat", category:.category, slot:.slot}
elif .screen == "pkgderived"
     then {screen:"category", category:.category}
elif .screen == "pkgderivedsrc"
     then {screen:"pkgderived", category:.category}
# A category returns to the top screen, on that category.
elif .screen == "category" then {screen:"top", focus:.category}
else {screen:"top"} end
