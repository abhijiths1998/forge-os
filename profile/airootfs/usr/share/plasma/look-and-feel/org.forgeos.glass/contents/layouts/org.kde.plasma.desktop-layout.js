// Forge Glass default desktop layout.
//
// plasmashell runs this once, for a user with no
// plasma-org.kde.plasma.desktop-appletsrc yet, from whichever look-and-feel
// package kdeglobals names (LookAndFeelPackage). Going through Plasma's own
// scripting API is what finally makes the dock compact and centred and the
// wallpaper stick; the hand-written appletsrc this replaces never managed
// either (see docs/ROADMAP.md).
//
// Shared by org.forgeos.glass and org.forgeos.glass.dark (symlinked).

// --- Top bar: launcher + app menu on the left, clock in the middle; on the
// right Forge Control, a slim tray (apps' icons), Wi-Fi, Bluetooth, Sound
// and the battery. Plasma centres whatever sits between two
// expanding spacers.
var bar = new Panel;
bar.location = "top";
bar.height = 2 * Math.ceil(gridUnit * 1.6 / 2);
bar.floating = true;
bar.opacity = "translucent";
bar.lengthMode = "fill";

var kickoff = bar.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "/usr/share/pixmaps/forge-os-emblem.png");
kickoff.writeConfig("favoritesDisplay", 0);

bar.addWidget("org.kde.plasma.appmenu");
bar.addWidget("org.kde.plasma.panelspacer");

var clock = bar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", 1);          // beside the time
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd, MMM d");

bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.forgeos.control");
// The tray stays for apps' own icons (Steam, Discord...). Plasma's items move
// to its overflow: Forge's Wi-Fi, Bluetooth, Sound and Battery show those
// instead, but Plasma's must keep running (the volume keys and notification
// pop-ups live in them), so they're hidden, not switched off.
var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("hiddenItems", [
    "org.kde.kdeconnect", "org.kde.plasma.vault", "org.kde.kscreen", "org.kde.kupapplet",
    "org.kde.plasma.battery", "org.kde.plasma.bluetooth", "org.kde.plasma.brightness",
    "org.kde.plasma.cameraindicator", "org.kde.plasma.clipboard", "org.kde.plasma.devicenotifier",
    "org.kde.plasma.dwellclicker", "org.kde.plasma.keyboardindicator", "org.kde.plasma.keyboardlayout",
    "org.kde.plasma.manage-inputmethod", "org.kde.plasma.mediacontroller",
    "org.kde.plasma.networkmanagement", "org.kde.plasma.notifications", "org.kde.plasma.printmanager",
    "org.kde.plasma.volume", "org.kde.plasma.weather",
]);
bar.addWidget("org.forgeos.wifi");
bar.addWidget("org.forgeos.bluetooth");
bar.addWidget("org.forgeos.volume");
bar.addWidget("org.forgeos.battery");

// --- Dock: floating, only as wide as its icons, centred.
var dock = new Panel;
dock.location = "bottom";
dock.height = 2 * Math.ceil(gridUnit * 3 / 2);
dock.floating = true;
dock.opacity = "translucent";
dock.lengthMode = "fit";
dock.alignment = "center";

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.forgeos.browser.desktop",
    "applications:steam.desktop",
    "applications:org.forgeos.store.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop",
]);
tasks.writeConfig("showOnlyCurrentDesktop", false);
tasks.writeConfig("iconSpacing", 2);

dock.addWidget("org.kde.plasma.marginsseparator");
dock.addWidget("org.kde.plasma.trash");

// --- Wallpaper: the ForgeGlass package has light and dark images, and the
// image plugin picks between them by colour scheme.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
    desktopsArray[j].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktopsArray[j].writeConfig("Image", "file:///usr/share/wallpapers/ForgeGlass/");
}
