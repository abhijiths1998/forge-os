-- Environment for the session and the apps it starts.
--
-- forge-gpu-env decides the GPU part: whether NVIDIA drives the screen (the
-- RTX 3050 laptop in its dGPU mode, desktops) or an integrated GPU does
-- (hybrid laptops, where forcing NVIDIA's GL on every app would drain the
-- battery). uwsm runs the same script before Hyprland starts
-- (/etc/xdg/uwsm/env-hyprland.d/50-forge.sh), which is what Hyprland itself
-- and systemd's user services see; this copy covers apps Hyprland starts.
local p = io.popen("forge-gpu-env 2>/dev/null")
if p then
    for line in p:lines() do
        local k, v = line:match("^export ([%w_]+)='(.*)'$")
        if k then hl.env(k, v) end
    end
    p:close()
end
