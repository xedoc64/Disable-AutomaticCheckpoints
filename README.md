# Disable-AutomaticCheckpoints


This script cant be used to disable automatic checkpoints when Hyper-V creates a new vm. These checkpoints are enabled in Hyper-V for Windows 11 per default.

## Usage

Clone the repo and store the Script in a folder of your choice.

For single usage until the hosts reboots just execute the script inside a powershell with administrative rights: `.\Disable-AutomaticCheckpoint.ps1 -Register`
To unregister run the script with the parameter `-Unregister`

To start the watcher on every boot you can run the script with the parameter `-InstallTask`, to remove the task use `-RemoveTask`. (Note that if the task is stopped it cannot disable the automatic checkpoints)


This script is tested with Windows 11 23H2.

Uses the idea to register event watcher from:
https://theposhwolf.com/howtos/PowerShell-On-Windows-Event/