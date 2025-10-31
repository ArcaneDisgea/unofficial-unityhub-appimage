# Unofficial UnityHub AppImage

> [!WARNING]  
> This repo and the releases in at are very much "Use at your own risk!"

## Notices

- This is an **unofficial** build of Unity Hub
- Unity Hub is proprietary software by Unity Technologies
- Use at your own risk
- For official builds, visit: https://unity.com/download
- Unity, please don't get mad.

## Why?

VRCHAT! For me personally... all I want to do is play with Unity Shaders at work.

## What works and what doesnt?

The things I did verify are as follows:
- Running it at all.
- Downloading and installing an editor.
- Using alcom to install packages.
- Opening the editor and importing a unitypackage.
    - I can't double click or drag and drop but going to the top menu and `Assets/Import Package` worked fine.
- Saving the scene, closing the editor, reopening it.

The things I did not try that immediately come to mind were:
- Build & Test
- Build & Upload
- Signing into the VRC SDK.

The things I noticed that need to be figured out:
- It checks for updates itself but because its the `deb` shoved into an `appimage` it tries to run the actual update commands using apt and all. This asks for `sudo` and prompts you. Click cancel because it will fail if you don't have those commands and if you do have those commands it may break something. 
    - ***This is your warning***, I am not responsible for what happens. I do intend to look into handling it.
- EULA might be skipped in some cases and that needs to be taken care of.

