local tag = "fuck_errors"

if SERVER then
    AddCSLuaFile("deps/luabsp.lua")
    AddCSLuaFile("includes/modules/deps/mdlinspect.lua")

    util.AddNetworkString(tag)

    resource.AddWorkshop("1604765873")

    hook.Add("PlayerSetModel", tag, function(ply)
        net.Start(tag)
        net.WriteEntity(ply)
        net.WriteBool(false)
        net.Broadcast()
    end)

    hook.Add("PlayerDisconnected", tag, function(ply)
        net.Start(tag)
        net.WriteEntity(ply)
        net.WriteBool(true)
        net.Broadcast()
    end)
end

if CLIENT then
    --require("deps/bspstaticprops")
    require("deps/mdlinspect")

    local luabsp = include("deps/luabsp.lua")
    local mapdata = luabsp.LoadMap(game.GetMap())

    mapdata:LoadLumps(43)
    mapdata:LoadStaticProps()

    local mapmaterials = mapdata.lumps[43].data
    local staticprops = mapdata.static_props

    CreateMaterial("no_errors_mat1", "VertexLitGeneric",
    {
        ["$basetexture"] = "no_errors/missing1",
        ["$basetexture2"] = "no_errors/missing1",
        ["$bumpmap"] = "no_errors/bump_missing1",
        ["$detail"] = "no_errors/missing1",
        ["$detailscale"] = "0",
        ["$detailblendmode"] = "0",
        ["$color"] = "1 1 1"
    })

    local errormodel = "models/error.mdl"
    local green = Color(0, 255, 0, 255)
    local orange = Color(255, 125, 0, 255)
    local white = Color(255, 255, 255, 255)
    local meta = FindMetaTable("Entity")

    -- bruh
    local Material = _G.Material
    local GetClass = meta.GetClass
    local GetPos = meta.GetPos
    local GetModel = meta.GetModel
    local GetAngles = meta.GetAngles
    local IsValid = meta.IsValid
    local GetAngles = meta.GetAngles
    local OBBMaxs = meta.OBBMaxs
    local OBBMins = meta.OBBMins
    local SetNoDraw = meta.SetNoDraw
    local IsMdlOk = util.IsModelLoaded

    local function Print(msg)
        MsgC(orange, "[NoErrors] ⮞ ", white, msg .. "\n")
    end

    local function IsNilOrEmptyString(str)
        return str == nil or (str:Trim() == "")
    end

    local function IsErrorTexture(text)
        return text:IsError() or (text:GetName() == "error")
    end

    local function SameInKeyValues(keyvalues, shader, text)
        local name1 = text and text:GetName() or nil
        local shadervalue = keyvalues[shader]
        local name2 = nil
        if type(shadervalue) == "ITexture" then
            name2 = shadervalue:GetName() or nil
        else
            name2 = shadervalue ~= nil and tostring(shadervalue) or nil
        end

        return name1 == name2
    end

    local exceptions = {["$basetexture2"] = true}
    local function ShouldFixShader(keyvalues, shader, txt)
        if not keyvalues[shader] and not exceptions[shader] then
            return false
        end

        return (txt and IsErrorTexture(txt)) or not SameInKeyValues(keyvalues, shader, txt)
    end

    local badshaders = {"water", "reflective"}
    local function HasBadShader(mat)
        for _, badshader in ipairs(badshaders) do
            if mat:GetShader():lower():find(badshader) then
                return true
            end
        end

        return false
    end

    local function TryFixMaterial(matpath)
        if matpath:match("^TOOLS") then return false end

        local mat = Material(matpath)
        if not mat then return true end

        if HasBadShader(mat) then return false end

        local waserror = false
        local keyvalues = mat:GetKeyValues()
        local isglass = matpath:lower():find("glass", 1, true)
        local basetxt = mat:GetTexture("$basetexture")
        local basetxtvalid = not ShouldFixShader(keyvalues, "$basetexture", basetxt)
        local basetxt2 = mat:GetTexture("$basetexture2")
        local basetxt2valid = not ShouldFixShader(keyvalues, "$basetexture2", basetxt2)
        local detailtxt = mat:GetTexture("$detail")

        if not basetxtvalid then
            mat:SetTexture("$basetexture", "no_errors/missing1")
            waserror = true
        end

        if not basetxt2valid then
            if not basetxtvalid or not basetxt then
                mat:SetTexture("$basetexture", "no_errors/missing1")
                mat:SetTexture("$basetexture2", "no_errors/missing1")
                waserror = true
            end
        end

        if ShouldFixShader(keyvalues, "$detail", detailtxt) then
            if (not basetxtvalid and basetxt) or (not basetxt2valid and basetxt2) then
                mat:SetTexture("$detail", "no_errors/missing1")
                mat:SetInt("$detailscale", 0)
                mat:SetInt("$detailblendmode", 0)
                waserror = true
            end
        end

        if waserror then
            if isglass then
                mat:SetInt("$no_draw", 1)
            end
        end

        return waserror
    end

    local function GetModelMaterials(mdlpath)
        local mdl = mdlinspect.Open(mdlpath)
        if not mdl then return {}, false end

        mdl:ParseHeader()

        local dirs = mdl:TextureDirs()
        local texturenames = mdl:Textures()
        local materials = {}
        local arevalid = true
        for _, dir in ipairs(dirs) do
            for _, textname in ipairs(texturenames) do
                local path = dir .. textname[1]
                if file.Exists(path, "GAME") then
                    local waserror = TryFixMaterial(path)
                    if waserror then
                        arevalid = false
                    end
                end
            end
        end
        mdl:Close()

        return materials, arevalid
    end

    local function FixStaticProps()
        local count = 0
        local done = {}
        for _, data in ipairs(staticprops) do
            for _, staticprop in pairs(data.entries) do
                if istable(staticprop) then
                    local mdlpath = staticprop.PropType
                    if mdlpath and not done[mdlpath] then
                        local materials, matsvalid = GetModelMaterials(mdlpath)
                        if IsMdlOk(mdlpath) then
                            if not matsvalid then
                                local csent = ents.CreateClientProp(mdlpath)
                                csent:SetMaterial("!no_errors_mat1")
                                csent:SetPos(staticprop.Origin)
                                csent:SetAngles(staticprop.Angles)
                                csent:SetModelScale(1.1)
                                csent:Spawn()
                                count = count + 1
                            end
                        else
                            done[mdlpath] = true
                        end
                    end
                end
            end
        end

        if count > 0 then
            Print("Fixed " .. count .. " map models")
        else
            Print("No map model to fix")
        end
    end

    local count = 0
    local checkedmats = {}
    local function ReplaceMissingMaterials(mats)
        for _, mat in pairs(mats) do
            if not checkedmats[mat] then
                local waserror = TryFixMaterial(mat)
                if waserror then
                    count = count + 1
                end
                checkedmats[mat] = true
            end
        end
    end

    local function HideErrorMaterial()
        local errormat = Material("models/error/new light1")
        errormat:SetInt("$alpha", 0)
        errormat:SetInt("$no_draw", 1)
        errormat:Recompute()
        Print("Got rid of error models")
    end

    hook.Add("InitPostEntity", tag, function()
        local preinit = SysTime()
        MsgC(orange, "- !*$%? ERRORS -\n")
        MsgC(orange, "-----------------------------------------------\n")
        Print("Initializing...")
        ReplaceMissingMaterials(mapmaterials)
        ReplaceMissingMaterials(game.GetWorld():GetMaterials())
        FixStaticProps()
        HideErrorMaterial()
        if count > 0 then
            Print("Fixed " .. count .. " missing materials")
        else
            Print("No materials to fix")
        end
        local diff = (SysTime() - preinit) * 1000
        Print(("Initialized in %.2fms"):format(diff))
        MsgC(orange, "-----------------------------------------------\n")
    end)

    local blacklist = {"vfire.*"}

    if file.Exists("no_error_blacklist.json", "DATA") then
        local content = file.Read("no_error_blacklist.json", "DATA") or ""
        local lines = ("\r?\n"):Explode(content)
        for _, line in ipairs(lines) do
            local class = line:Trim()
            if #class > 0 then
                table.insert(blacklist, line)
            end
        end
    end

    concommand.Add("no_error_blacklist", function(_, _, _, arg)
        local class = arg:Trim()
        if #class == 0 then return end
        table.insert(blacklist, class)
        file.Append("no_error_blacklist.json", "\n" .. class)
        Print(("Added \'%s\' to the blacklist"):format(class))
    end, nil, "Blacklist a class from being modified")

    local function IsBlacklisted(ent)
        for _, class in ipairs(blacklist) do
            if GetClass(ent):match(class) then
                return true
            end
        end

        return false
    end

    local ents = {}
    local lookup = {}
    local done = {}
    local function RegisterEnt(ent)
        if not IsValid(ent) then return end
        if IsBlacklisted(ent) then return end

        local model = GetModel(ent)
        if model == errormodel then
            local i = table.insert(ents, ent)
            lookup[ent] = i
        end
        if model and not done[model] then
            ReplaceMissingMaterials(ent:GetMaterials())
            done[model] = true
        end
    end

    local function UnregisterEnt(ent)
        if not IsValid(ent) then return end

        local i = lookup[ent]
        if i then
            table.remove(ents, i)
            lookup[ent] = nil
        end
    end

    hook.Add("NetworkEntityCreated", tag, RegisterEnt)
    hook.Add("EntityRemoved", tag, UnregisterEnt)

    net.Receive(tag, function()
        local ply = net.ReadEntity()
        local disconnected = net.ReadBool()
        if not IsValid(ply) then return end
        if disconnected then
            UnregisterEnt(ply)
        else
            if GetModel(ply) == errormodel then
                RegisterEnt(ply)
            else
                UnregisterEnt(ply)
            end
        end
    end)

    local Box = render.DrawWireframeBox
    local function DrawHitboxes()
        for _, ent in ipairs(ents) do
            if IsValid(ent) then
                local pos = GetPos(ent)
                local ang = GetAngles(ent)
                local mins = OBBMins(ent)
                local maxs = OBBMaxs(ent)
                Box(pos, ang, mins, maxs, green, true)
                SetNoDraw(ent, true)
            end
        end
    end

    local cvar = CreateClientConVar("no_error_hitboxes", "1", true, false, "Shows error model hitboxes")
    if cvar:GetBool() then
        hook.Add("PostDrawTranslucentRenderables", tag, DrawHitboxes)
    end

    cvars.AddChangeCallback("no_error_hitboxes", function()
        if cvar:GetBool() then
            hook.Add("PostDrawTranslucentRenderables", tag, DrawHitboxes)
        else
            hook.Remove("PostDrawTranslucentRenderables", tag)
            for _, ent in ipairs(ents) do
                if IsValid(ent) then
                    SetNoDraw(ent, false)
                end
            end
        end
    end)
end
