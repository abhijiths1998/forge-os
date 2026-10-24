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

// --- Top bar: launcher + app menu on the left, clock in the middle, Forge
// Control, the tray and Forge Battery on the right. Plasma centres whatever sits between two
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
var tray = bar.addWidget("org.kde.plasma.systemtray");
// Forge Battery (next) shows the battery; Plasma's own moves to the tray's
// overflow, where its power settings stay a click away.
tray.currentConfigGroup = ["General"];
tray.writeConfig("hiddenItems", ["org.kde.plasma.battery"]);
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
