# Minecraft Modpack Manager Reborn
> An easy way to manage your modpacks, written in Dart and Flutter
### Working features:
* #### Applying modpacks
* #### Clearing modpacks
* #### Reloading modpacks in the list
* #### Opening modpacks folder
* #### Installing modpacks using .mcmodpackref
* #### Installing mods and resourcepacks (not modpacks) from curseforge/modrinth


### [Available on Flathub](https://flathub.org/apps/details/dev.mrquantumoff.mcmodpackmanager)
### [Available on Microsoft Store*](https://www.microsoft.com/store/apps/9NLT70M0TVD0)

#### [Available on Snap Store**](https://snapcraft.io/mcmodpackmanager)

> ## *ENABLE Developer mode on windows, or else the app won't work!
> ### Warning: If your mods folder is not symlinked to modpacks/<anything> your mods folder will be deleted after you apply/clear your modpack.
> #### Warning: Some features may not work properly on macOS, since I don't have a Mac and I can't test the app on it. If you have one and you know how to code, please submit a pr.
> #### **With the snap store you may need to symlink the snap user data `.minecraft` folder to `~/.minecraft`, but if you have flatpak installed, I recommend to use flatpak, it's a smoother experience.
> Why can't I include modpacks from curseforge? Although I do have API access to curseforge modpack API, I cannot completely install everything from a modpack, since many modpacks tend to overwrite some of minecraft's settings and/or install external resource packs. I do not wish to deal with that. I may include resource pack support in the future though.