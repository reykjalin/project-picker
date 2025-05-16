# Project picker

Presents a filterable list of pre-defined strings from `~/.config/project-picker/projects` for you to select and provide to some shell command.
Once an item in the list is selected `project-picker` will print the full path to STDOUT.

**Exit codes:**

* If an item is picked `project-picker` will exit with status `0`.
* If no item is chosen `project-picker` will exit with status `1`.
* If `Ctrl-C` is used to close `project-picker` instead of selecting an item it will exit with status `1`.
* If an error occurred `project-picker` will exit with status `74` and an error message is printed to STDERR.

## Usage example: jump between project folders

Add a list of the projects you want easily available to a config file, then run `project-picker`.
`project-picker` will print the selected project path to STDOUT.

### Add project paths to the config file

```
~/projects/project-a
~/projects/project-b
/Users/jdoe/projects/project-c
~/projects/sub-projects/*
```

If you end a path with `/*` `project-picker` will list all the directories in that folder.

### Example: jump between projects with cd

Put in a shell script or alias:

```fish
# ~/.config/fish/functions/pp.fish
# Fish alias for project-picker, usage: pp
function pp
  set dir (project-picker)

  # A non-zero exit code means no project was selected.
  if test $status -eq 0
      cd $dir
  end
end
```


## Usage example: pass result to command

This is the quick and dirty way to use `project-picker`.
If an error occurs or you don't pick an item nothing will be passed to the command.

```bash
# `cd` to selected item.
cd $(project-picker)

# Open selected item in vim.
vim $(project-picker)
```


## Build `project-picker`

```sh
# Will place `project-picker` in ./zig-out/bin
zig build -Doptimize=ReleaseSafe

# Will place `project-picker` in ~/.local/bin
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

