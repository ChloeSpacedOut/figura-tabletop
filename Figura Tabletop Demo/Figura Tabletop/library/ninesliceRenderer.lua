---@class NinesliceRenderer: LoamRenderer
---@field part ModelPart
---@field depth number
local NinesliceRenderer = {}
NinesliceRenderer.__index = NinesliceRenderer

---@class Nineslice
---@field texture Texture
---@field slice_size number

---@param part ModelPart
function NinesliceRenderer.new(part)
    local self = setmetatable({}, NinesliceRenderer)
    self.part = part
    self.depth = 0
    self.to_draw = {}
    self.rendering = {}
    self.last_frame = {}
    return self
end

function NinesliceRenderer:draw_nineslice(pos, size, slice_tex, slice_size, slice_index, colour, depth)
    local index = table.concat({ pos.x, pos.y, size.x, size.y, tostring(slice_tex), slice_size, slice_index, colour.x, colour.y, colour.z, colour.w or 1, depth })

    local to_draw = self.to_draw
    local rendering = self.rendering

    to_draw[index] = function()
        local texture = slice_tex
        local dims = texture:getDimensions()

        local slice = slice_size

        local inner_width = size.x - (slice * 2)
        local inner_height = size.y - (slice * 2)

        local slice_offset = slice_index * slice * 3

        for i = 0, 2 do
            for j = 0, 2 do
                local uv_x = j * slice + slice_offset
                local uv_y = i * slice

                local pos_x = (j == 1) and slice or (j == 2 and size.x - slice or 0)
                local pos_y = (i == 1) and slice or (i == 2 and size.y - slice or 0)

                local scale_x = (j == 1) and inner_width / slice or 1
                local scale_y = (i == 1) and inner_height / slice or 1

                if size.x > slice and size.y > slice then
                    rendering[self.part:newSprite(index .. i .. j)
                        :texture(texture, dims.x, dims.y)
                        :size(slice, slice)
                        :uvPixels(uv_x, uv_y)
                        :region(slice, slice)
                        :pos(-pos.x - pos_x, -pos.y - pos_y, -depth)
                        :scale(scale_x, scale_y)
                        :renderType("CUTOUT_EMISSIVE_SOLID")
                        :color(colour)] = index
                end
            end
        end
    end
end

local tex = textures["1x1white"] or textures:newTexture("1x1white",1,1):setPixel(0,0,vectors.vec3(1,1,1))
function NinesliceRenderer:draw_rect(pos, size, colour, depth)
    local index = table.concat({ pos.x, pos.y, size.x, size.y, colour.r, colour.g, colour.b, colour.a or 1, depth })

    local to_draw = self.to_draw
    local rendering = self.rendering

    to_draw[index] = function()
        rendering[self.part:newSprite(index)
            :texture(tex, 1, 1)
            :pos(-pos.x, -pos.y, -depth)
            :scale(size.x, size.y)
            :color(colour)
            :renderType("CUTOUT_EMISSIVE_SOLID")] = index
    end
end

function NinesliceRenderer:draw_text(pos, text, text_scale, text_width, shadow, depth)
    local index = table.concat({ pos.x, pos.y, text, text_scale, text_width or 0, tostring(shadow), depth })

    local to_draw = self.to_draw
    local rendering = self.rendering

    to_draw[index] = function()
        rendering[self.part:newText(index)
            :text(text)
            :shadow(shadow)
            :scale(text_scale, text_scale, 0.01)
            :width(text_width / text_scale)
            :light(15, 15)
            :pos(-pos.x, -pos.y, -depth)] = index
    end
end

function NinesliceRenderer:draw_item(pos, size, item, depth)
    local index = table.concat({ pos.x, pos.y, size.x, size.y, item, depth })

    local to_draw = self.to_draw
    local rendering = self.rendering

    to_draw[index] = function()
        rendering[self.part:newItem(index)
            :item(item)
            :displayMode("GUI")
            :scale(size.x / 16, size.y / 16, 0.00001)
            :overlay(0, 15)
            :pos(-pos.x - size.x / 2, -pos.y - size.y / 2, -depth)] = index
    end
end

function NinesliceRenderer:draw_texture(pos, size, texture, depth)
    local index = table.concat({ pos.x, pos.y, size.x, size.y, tostring(texture), depth })

    local to_draw = self.to_draw
    local rendering = self.rendering

    to_draw[index] = function()
        local texture_size = texture.texture:getDimensions()
        local tile = texture.tile

        local tex_region = texture.region or texture_size

        local region = tile
            and vec(tex_region.x * (size.x / texture_size.x), tex_region.y * (size.y / texture_size.y))
            or tex_region

        if texture.snap then
            texture.uv = (texture.uv / texture.snap):floor() * texture.snap
        end

        local uv = texture.uv or vec(0, 0)

        local sprite = self.part:newSprite(index)
            :texture(texture.texture, texture.dimensions or texture_size)
            :dimensions(texture.dimensions or texture_size)
            :region(region)
            :uv(uv.x / texture_size.x, uv.y / texture_size.y)
            :pos(-pos.x, -pos.y, -depth)
            :scale(size.x / texture_size.x, size.y / texture_size.y)
            :renderType(texture.render_type or "CUTOUT")

        local vs = sprite:getVertices()
        if self.part:getParentType() == "Hud" then
            vs[1]:setNormal(0, 1, 0)
            vs[2]:setNormal(0, 1, 0)
            vs[3]:setNormal(0, 1, 0)
            vs[4]:setNormal(0, 1, 0)
        end

        rendering[sprite] = index
    end
end

function NinesliceRenderer:draw_all()
    local to_draw = self.to_draw
    local rendering = self.rendering
    local last_frame = self.last_frame

    for index, func in pairs(to_draw) do
        if not last_frame[index] then
            func()
        end
    end

    for task, index in pairs(rendering) do
        if not to_draw[index] then
            task:remove()
            rendering[task] = nil
        end
    end

    self.last_frame = to_draw
    self.to_draw = {}
end

function NinesliceRenderer:clear()
    for task in pairs(self.rendering) do
        task:remove()
    end
    self.rendering = {}
    self.last_frame = {}
    self.to_draw = {}
end

return NinesliceRenderer