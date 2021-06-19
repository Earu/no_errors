local tag = "no_errors"

if SERVER then
    AddCSLuaFile("deps/luabsp.lua")
    AddCSLuaFile("includes/modules/deps/mdlinspect.lua")

    util.AddNetworkString(tag)

    resource.AddWorkshop("1604765873")

    --[[hook.Add("PlayerSetModel", tag, function(ply)
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
    end)]]--
end

if CLIENT then
    module("no_errors", package.seeall)

    --require("deps/bspstaticprops")
    require("deps/mdlinspect")

    local luabsp = include("deps/luabsp.lua")
    local mapdata = luabsp.LoadMap(game.GetMap())

    mapdata:LoadLumps(43)
    mapdata:LoadStaticProps()

    local map_materials = mapdata.lumps[43].data
    local static_props = mapdata.static_props

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

    local error_model = "models/error.mdl"
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
    local OBBMaxs = meta.OBBMaxs
    local OBBMins = meta.OBBMins
    local SetNoDraw = meta.SetNoDraw
    local IsMdlOk = util.IsModelLoaded

    local function Print(msg)
        MsgC(orange, "[NoErrors] ⮞ ", white, msg .. "\n")
    end

    function IsErrorTexture(texture)
        return texture:IsError() or (texture:GetName() == "error")
    end

    function SameInKeyValues(key_values, shader, texture)
        local shader_value = key_values[shader]
        if texture and shader_value and type(shader_value) == "ITexture" then
            return texture:GetName() == shader_value:GetName()
        end

        if not texture and not shader_value then return true end

        return false
    end

    --local exceptions = { ["$basetexture2"] = true }
    function ShouldFixShader(key_values, shader, texture)
        if not key_values[shader] then return false end
        return (texture and IsErrorTexture(texture)) or not SameInKeyValues(key_values, shader, texture)
    end

    local bad_shaders = { "water", "reflective" }
    function HasBadShader(material)
        for _, bad_shader in ipairs(bad_shaders) do
            if material:GetShader():lower():find(bad_shader) then
                return true
            end
        end

        return false
    end

    function TryFixMaterial(material_path)
        if material_path:match("^TOOLS") then return false end -- skybox materials

        local material = Material(material_path)
        if not material then return true end

        if HasBadShader(material) then return false end

        local was_error = false
        local key_values = material:GetKeyValues()

        local base_texture = material:GetTexture("$basetexture")
        local should_fix_base_texture = ShouldFixShader(key_values, "$basetexture", base_texture)

        local base_texture2 = material:GetTexture("$basetexture2")
        local should_fix_base_texture2 = ShouldFixShader(key_values, "$basetexture2", base_texture2)

        if should_fix_base_texture then
            material:SetTexture("$basetexture", "no_errors/missing1")
            was_error = true
        end

        if should_fix_base_texture2 then
            material:SetTexture("$basetexture2", "no_errors/missing1")
            was_error = true
        end

        local detail_texture = material:GetTexture("$detail")
        if ShouldFixShader(key_values, "$detail", detail_texture) and (base_texture or base_texture2) then
            material:SetTexture("$detail", "no_errors/missing1")
            material:SetInt("$detailscale", 0)
            material:SetInt("$detailblendmode", 0)
            was_error = true
        end

        if was_error and material_path:lower():find("glass", 1, true) then
            material:SetInt("$no_draw", 1)
        end

        return was_error
    end

    function GetModelMaterials(model_path)
        local mdl = mdlinspect.Open(model_path)
        if not mdl then return {}, false end

        mdl:ParseHeader()

        local dirs = mdl:TextureDirs()
        local texture_names = mdl:Textures()
        local materials = {}
        local valid_materials = true
        for _, dir in ipairs(dirs) do
            for _, texture_name in ipairs(texture_names) do
                local path = dir .. texture_name[1]
                if file.Exists(path, "GAME") then
                    local was_error = TryFixMaterial(path)
                    if was_error then
                        valid_materials = false
                    end
                end
            end
        end

        mdl:Close()

        return materials, valid_materials
    end

    function FixStaticProps()
        local count = 0
        local done = {}
        for _, data in ipairs(static_props) do
            for _, static_prop in pairs(data.entries) do
                if istable(static_prop) then
                    local model_path = static_prop.PropType
                    if model_path and not done[model_path] then
                        local _, valid_materials = GetModelMaterials(model_path)
                        if IsMdlOk(model_path) then
                            if not valid_materials then
                                local client_entity = ents.CreateClientProp(model_path)
                                client_entity:SetMaterial("!no_errors_mat1")
                                client_entity:SetPos(static_prop.Origin)
                                client_entity:SetAngles(static_prop.Angles)
                                client_entity:SetModelScale(1.1)
                                client_entity:Spawn()
                                count = count + 1
                            end
                        else
                            done[model_path] = true
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
    local checked_materials = {}
    function ReplaceMissingMaterials(materials)
        for _, material in pairs(materials) do
            if not checked_materials[material] then
                local was_error = TryFixMaterial(material)
                if was_error then
                    count = count + 1
                end

                checked_materials[material] = true
            end
        end
    end

    function HideErrorMaterial()
        local error_material = Material("models/error/new light1")
        error_material:SetInt("$alpha", 0)
        error_material:SetInt("$no_draw", 1)
        error_material:Recompute()

        Print("Got rid of error models")
    end

    hook.Add("InitPostEntity", tag, function()
        local pre_init_time = SysTime()
        MsgC(orange, "- !*$%? ERRORS -\n")
        MsgC(orange, "-----------------------------------------------\n")
        Print("Initializing...")

        ReplaceMissingMaterials(map_materials)
        ReplaceMissingMaterials(game.GetWorld():GetMaterials())
        FixStaticProps()
        HideErrorMaterial()

        if count > 0 then
            Print("Fixed " .. count .. " missing materials")
        else
            Print("No materials to fix")
        end

        Print(("Initialized in %.2fms"):format((SysTime() - pre_init_time) * 1000))
        MsgC(orange, "-----------------------------------------------\n")
    end)

    local blacklist = {"vfire.*", "Player"}
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

    function IsBlacklisted(ent)
        if ent:GetNoDraw() then return true end

        for _, class in ipairs(blacklist) do
            if GetClass(ent):match(class) then
                return true
            end
        end

        return false
    end

    local entities = {}
    local lookup = {}
    local done = {}
    function RegisterEnt(ent)
        if not IsValid(ent) then return end
        if IsBlacklisted(ent) then return end

        local model = GetModel(ent)
        if model == error_model then
            local i = table.insert(entities, ent)
            lookup[ent] = i
        end

        if model and not done[model] then
            ReplaceMissingMaterials(ent:GetMaterials())
            done[model] = true
        end
    end

    function UnregisterEnt(ent)
        if not IsValid(ent) then return end

        local i = lookup[ent]
        if i then
            table.remove(entities, i)
            lookup[ent] = nil
        end
    end

    hook.Add("OnEntityCreated", tag, function(ent)
        timer.Simple(0.25, function() -- maybe too early otherwise
            RegisterEnt(ent)
        end)
    end)

    hook.Add("EntityRemoved", tag, UnregisterEnt)

    --[[net.Receive(tag, function()
        local ply = net.ReadEntity()
        local disconnected = net.ReadBool()
        if not IsValid(ply) then return end
        if disconnected then
            UnregisterEnt(ply)
        else
            if GetModel(ply) == error_model then
                RegisterEnt(ply)
            else
                UnregisterEnt(ply)
            end
        end
    end)]]--

    local Box = render.DrawWireframeBox
    local function DrawHitboxes()
        for _, ent in ipairs(entities) do
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
            for _, ent in ipairs(entities) do
                if IsValid(ent) then
                    SetNoDraw(ent, false)
                end
            end
        end
    end)
end
