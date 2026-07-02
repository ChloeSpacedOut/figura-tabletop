local FIT_SIZING = 1e300
local GROW_SIZING = 1e301
local FIXED_SIZING = 1e302

---@class Node
---@field parent Node
---@field children Node[]
local Node = {}
Node.__index = Node

---@class LoamElement
---@field children List
---@field parent LoamElement
---@field pos Vector2
---@field anchor Vector2
---@field size Vector2
---@field size_offset Vector2?
---@field size_mode Vector2
---@field background_colour Vector3?
---@field hover_colour Vector3?
---@field padding [number, number, number, number]
---@field child_gap number
---@field direction "HORIZONTAL"|"VERTICAL"
---@field alignment_horizontal "LEFT"|"CENTRE"|"RIGHT"
---@field alignment_vertical "TOP"|"CENTRE"|"BOTTOM"
---@field part ModelPart
---@field text string?
---@field hover_text string?
---@field text_scale number?
---@field is_emoji boolean?
---@field item string?
---@field right_align boolean
---@field texture { texture: Texture, size: Vector2, uv: Vector2 }?
---@field nineslice { texture: Texture, size: integer, index: integer, colour: Vector3 }?
---@field click fun(self: self)?
---@field scroll fun(self: self, scroll_state: integer)?
---@field deferred fun(self: self)?
---@field floating boolean
---@field slice integer
local LoamElement = {}
LoamElement.__index = LoamElement

local DEFAULTS = {
    pos = vec(0, 0),
    anchor = vec(0, 0),
    size = vec(FIT_SIZING, FIT_SIZING),
    size_mode = vec(FIT_SIZING, FIT_SIZING),
    background_colour = nil,
    hover_colour = nil,
    padding = { 0, 0, 0, 0 },
    child_gap = 0,
    direction = "HORIZONTAL",
    alignment_horizontal = "LEFT",
    alignment_vertical = "TOP",
    floating = false,
    held_click = false,
    slice = 0,
}
local INHERIT = { __index = setmetatable(DEFAULTS, { __index = LoamElement }) }
local SIZE_MODE_MAP = {
    [FIT_SIZING] = FIT_SIZING,
    [GROW_SIZING] = GROW_SIZING,
    [FIXED_SIZING] = FIXED_SIZING,
}

function LoamElement.new(data)
    local self = setmetatable({}, { __index = setmetatable(data, INHERIT) })
    self.children = list({})

    local data_size = data.size
    if data_size then
        local dsx = data_size.x
        local dsy = data_size.y
        local mapped_x = SIZE_MODE_MAP[dsx]
        local mapped_y = SIZE_MODE_MAP[dsy]
        self.size_mode = vec(
            mapped_x or FIXED_SIZING,
            mapped_y or FIXED_SIZING
        )
        self.size = vec(
            mapped_x and 0 or dsx,
            mapped_y and 0 or dsy
        )
    end

    return self
end

---@param callback fun(child: LoamElement)?
function LoamElement:child(data, callback)
    local child = LoamElement.new(data)

    if callback then
        callback(child)
    end

    child.parent = self
    self.children:push(child)

    return child
end

function LoamElement:with(fn)
    fn(self)
    return self
end

local function within_bounds(pos, size, mouse_pos)
    return mouse_pos.x >= pos.x and mouse_pos.x <= (pos.x + size.x) and
        mouse_pos.y >= pos.y and mouse_pos.y <= (pos.y + size.y)
end

local d = 0
local held_clicking = {}
---@param renderer LoamRenderer
---@param mouse_pos Vector2
---@param mouse_state integer
---@param scroll_state integer
function LoamElement:draw_children(renderer, mouse_pos, mouse_state, scroll_state, check_hover, depth, hover_checks)
    depth = depth or 0.001

    local left_offset = self.padding[1]
    local top_offset = self.padding[2]

    self.children:each(function(child)
        local child_pos = self.pos + child.pos

        if child.alignment_horizontal == "LEFT" then
            child_pos.x = child_pos.x + left_offset - child.size.x * child.anchor.x
        elseif child.alignment_horizontal == "RIGHT" then
            child_pos.x = child_pos.x + self.size.x - child.size.x - left_offset
        elseif child.alignment_horizontal == "CENTRE" then
            child_pos.x = self.pos.x + self.size.x / 2 + child.pos.x - child.size.x / 2
        end

        if child.alignment_vertical == "TOP" then
            child_pos.y = child_pos.y + top_offset - child.size.y * child.anchor.y
        elseif child.alignment_vertical == "BOTTOM" then
            child_pos.y = child_pos.y + top_offset + self.size.y - child.size.y - self.padding[4]
        elseif child.alignment_vertical == "CENTRE" then
            child_pos.y = self.pos.y + self.size.y / 2 + child.pos.y - child.size.y / 2
        end

        -- if child.floating then
        --     child_pos.y = child_pos.y - top_offset
        -- end

        child.pos = child_pos

        local is_hovering = false
        if check_hover ~= false or self.has_floating then
            is_hovering = self.is_hovering or within_bounds(child_pos, child.size, mouse_pos)
            if child.cascade_hover then
                child.is_hovering = is_hovering
            end
        end

        if child.hover_colour or child.hover_nineslice or child.hover_text then
            hover_checks:push(function(mouse_pos)
                return within_bounds(child_pos, child.size, mouse_pos)
            end)
        end

        local held_click = held_clicking[renderer]
        if child.click and (not held_click and true or held_click == depth) then
            if (mouse_state == 1 or (child.held_click and mouse_state == 2)) and (is_hovering or held_click == depth) then
                child:click(vec(
                    math.clamp((mouse_pos.x - child_pos.x) / child.size.x, 0, 1),
                    math.clamp((mouse_pos.y - child_pos.y) / child.size.y, 0, 1)
                ), vec(mouse_pos.x - child_pos.x, mouse_pos.y - child_pos.y), mouse_state)

                if child.held_click then
                    held_clicking[renderer] = depth
                end
            end
        end

        if child.release then
            if mouse_state == 0 and (is_hovering or held_clicking[renderer] == depth) then
                child:release()
            end
        end

        if child.scroll then
            if scroll_state ~= 0 and is_hovering then
                child.scroll(scroll_state)
            end
        end

        d = d + 0.0000001
        if self.floating then
            depth = depth + 0.01 + d
        else
            depth = depth + 0.0001 + d
        end

        local outset = child.outline_colour and 0.001 or 0
        if child.background_colour then
            if child.hover_colour and is_hovering then
                renderer:draw_rect(child_pos, child.size, child.hover_colour, depth + outset)
            else
                renderer:draw_rect(child_pos, child.size, child.background_colour, depth + outset)
            end
        end

        if child.outline_colour then
            renderer:draw_rect(child_pos - vec(1, 1), child.size + vec(1, 1) * 2, child.outline_colour, depth + outset * 0.9)
        end

        if child.nineslice then
            if child.hover_nineslice and is_hovering then
                local hover = child.hover_nineslice
                renderer:draw_nineslice(child_pos, child.size, hover.texture, hover.size, hover.index, hover.colour, depth + outset)
            else
                local slice = child.nineslice
                renderer:draw_nineslice(child_pos, child.size, slice.texture, slice.size, slice.index, slice.colour, depth + outset)
            end
        end

        if child.text then
            local pad_size = (self.padding and (self.padding[1] + self.padding[3]) or 0)
            local shadow = child.shadow == nil and true or child.shadow
            if child.hover_text and is_hovering then
                renderer:draw_text(child_pos, child.hover_text, child.text_scale or 1, child.size.x + pad_size, shadow, depth + outset + 0.001)
            else
                renderer:draw_text(child_pos, child.text, child.text_scale or 1, child.size.x + pad_size, shadow, depth + outset + 0.001)
            end

            if child.right_align then
                child.pos.x = child_pos.x - client.getTextWidth(child.text) + child.size.x
            end
        end

        if child.item then
            renderer:draw_item(child_pos, child.size, child.item, depth)
        end

        if child.texture then
            renderer:draw_texture(child_pos, child.size, child.texture, depth)
        end

        if not child.floating then
            if self.direction == "HORIZONTAL" then
                left_offset = left_offset + child.size.x + self.child_gap
            else
                top_offset = top_offset + child.size.y + self.child_gap
            end
        end

        if child.deferred then
            child:deferred(child_pos, is_hovering, mouse_pos)
        end

        child:draw_children(renderer, mouse_pos, mouse_state, scroll_state, is_hovering, depth, hover_checks)
    end)

    return self
end

local clamp_cache = setmetatable({}, { mode = "v" })
---@param text string
---@param max_width number
---@return string
local function clamp_text(text, max_width)
    if clamp_cache[text] and clamp_cache[text][max_width] then
        return clamp_cache[text][max_width]
    end

    local width = client.getTextWidth(text)

    local i = 0
    if width > max_width then
        local ellipsis = "..."
        local ellipsis_width = client.getTextWidth(ellipsis)
        local truncated_text = text

        local low, high = 0, #truncated_text
        while low < high do
            i = i + 1
            local mid = math.floor((low + high) / 2)
            local test_text = truncated_text:sub(1, mid)
            local test_width = client.getTextWidth(test_text)

            if test_width + ellipsis_width > max_width then
                high = mid
            else
                low = mid + 1
            end
        end

        local out = low > 0 and truncated_text:sub(1, low - 1) .. ellipsis or ellipsis
        clamp_cache[text] = clamp_cache[text] or {}
        clamp_cache[text][max_width] = out

        return out
    end

    return text
end

function LoamElement:calculate_sizes()
    self.children:each(LoamElement.calculate_sizes)

    if self.children:count() > 0 then
        local total_width = 0
        local total_height = 0
        local max_child_width = 0
        local max_child_height = 0

        self.children:each(function(child)
            if not child.floating then
                if self.direction == "HORIZONTAL" then
                    total_width = total_width + child.size.x
                    max_child_height = math.max(max_child_height, child.size.y)
                else
                    total_height = total_height + child.size.y
                    max_child_width = math.max(max_child_width, child.size.x)
                end
            end
        end)

        local non_floating_count = 0
        self.children:each(function(child)
            if not child.floating then
                non_floating_count = non_floating_count + 1
            end
        end)

        local gaps = self.child_gap * math.max(0, non_floating_count - 1)
        if self.direction == "HORIZONTAL" then
            total_width = total_width + gaps
        else
            total_height = total_height + gaps
        end

        if self.direction == "HORIZONTAL" then
            self.size.x = math.max(self.size.x, total_width)
            self.size.y = math.max(self.size.y, max_child_height)
        else
            self.size.x = math.max(self.size.x, max_child_width)
            self.size.y = math.max(self.size.y, total_height)
        end

        self.size.x = self.size.x + self.padding[1] + self.padding[3]
        self.size.y = self.size.y + self.padding[2] + self.padding[4]
    end

    if self.text then
        if self.is_emoji then
            self.size.x = 9 * (self.text_scale or 1)
            self.size.y = 9 * (self.text_scale or 1)
        else
            local stripped_text = self.text:gsub(":[%w_@]-:", "a")
            if self.size_mode.x == FIT_SIZING then
                self.size.x = client.getTextWidth(stripped_text) * (self.text_scale or 1)
            elseif self.size_mode.x == GROW_SIZING then
                self.size.x = client.getTextWidth(stripped_text) * (self.text_scale or 1)
            elseif self.size_mode.x == FIXED_SIZING then
                if self.wrap_text then
                    self.size.x = self.size.x * (self.text_scale or 1)
                    self.size.x = math.min(self.size.x, client.getTextDimensions(stripped_text, self.size.x, true).x)
                else
                    if client.getTextWidth(stripped_text) > self.size.x then
                        self.text = clamp_text(self.text, self.size.x)
                        if self.hover_text then
                            self.hover_text = clamp_text(self.hover_text, self.size.x)
                        end
                    end
                end
            end

            if self.size_mode.y ~= FIXED_SIZING then
                self.size.y = (self.wrap_text and math.max(9, client.getTextDimensions(stripped_text, self.size.x / (self.text_scale or 1), true).y) or 9) * (self.text_scale or 1)
                -- self.size.y = client.getTextDimensions(stripped_text, self.size.x / (self.text_scale or 1), true).y * (self.text_scale or 1)
            end
        end
    end

    return self
end

function LoamElement:propagate_sizes()
    if self.direction == "VERTICAL" then
        local available_width = self.size.x - (self.padding[1] + self.padding[3])

        self.children:each(function(child)
            if not child.floating and child.size_mode.x == GROW_SIZING and child.size.x < available_width then
                child.size.x = available_width
            end
        end)
    elseif self.direction == "HORIZONTAL" then
        local available_height = self.size.y - (self.padding[2] + self.padding[4])

        self.children:each(function(child)
            if not child.floating and child.size_mode.y == GROW_SIZING and child.size.y < available_height then
                child.size.y = available_height
            end
        end)
    end

    self.children:each(LoamElement.propagate_sizes)

    return self
end

function LoamElement:distribute_space()
    local grow_count_x = 0
    local grow_count_y = 0

    self.children:each(function(child)
        if not child.floating then
            if child.size_mode.x == GROW_SIZING then
                grow_count_x = grow_count_x + 1
            end

            if child.size_mode.y == GROW_SIZING then
                grow_count_y = grow_count_y + 1
            end
        end
    end)

    local available_width = self.size.x - (self.padding[1] + self.padding[3])
    local available_height = self.size.y - (self.padding[2] + self.padding[4])

    local used_width = 0
    local used_height = 0

    self.children:each(function(child)
        if not child.floating then
            if child.size_mode.x ~= GROW_SIZING then
                if self.direction == "HORIZONTAL" then
                    used_width = used_width + child.size.x
                end
            end

            if child.size_mode.y ~= GROW_SIZING then
                if self.direction == "VERTICAL" then
                    used_height = used_height + child.size.y
                end
            end
        end
    end)

    local floating_count = 0
    local non_floating_count = 0
    self.children:each(function(child)
        if child.floating then
            floating_count = floating_count + 1
        else
            non_floating_count = non_floating_count + 1
        end
    end)

    if floating_count > 0 then
        self.has_floating = true
    end

    local gaps = self.child_gap * math.max(0, non_floating_count - 1)
    if self.direction == "HORIZONTAL" then
        used_width = used_width + gaps
    else
        used_height = used_height + gaps
    end

    local remaining_width = available_width - used_width
    local remaining_height = available_height - used_height

    local width_per_grow = grow_count_x > 0 and remaining_width / grow_count_x or 0
    local height_per_grow = grow_count_y > 0 and remaining_height / grow_count_y or 0

    self.children:each(function(child)
        if not child.floating then
            if child.size_mode.x == GROW_SIZING then
                if self.direction == "HORIZONTAL" then
                    child.size.x = math.max(0, width_per_grow)
                else
                    child.size.x = available_width
                end
            end

            if child.size_mode.y == GROW_SIZING then
                if self.direction == "VERTICAL" then
                    child.size.y = math.max(0, height_per_grow)
                else
                    child.size.y = available_height
                end
            end

            if child.size_offset then
                child.size.x = child.size.x + (remaining_width * child.size_offset.x)
                child.size.y = child.size.y + (remaining_height * child.size_offset.y)
            end
        end
    end)

    self.children:each(LoamElement.distribute_space)

    return self
end

-- require("globals.profiler")
-- profiler.wrap(LoamElement)
-- events.tick = profiler.readout

---@class Loam
local Loam = {}

Loam.GROW = GROW_SIZING
Loam.FIT = FIT_SIZING

---@class LoamRenderer
---@field draw_rect fun(self: self, pos: Vector2, size: Vector2, colour: Vector3)
---@field draw_text fun(self: self, pos: Vector2, text: string)
---@field draw_item fun(self: self, pos: Vector2, size: Vector2, item: string)
---@field draw_texture fun(self: self, pos: Vector2, size: Vector2, texture: { texture: Texture, size: Vector2, uv: Vector2 })

---@type Event.Press.state
local mouse_state = 0

local scroll_state = 0

local CLICK = keybinds:of("loam:click", "key.mouse.left", true)

function CLICK:press()
    mouse_state = 1
end

function CLICK:release()
    mouse_state = 0
end

function events.MOUSE_SCROLL(dir)
    scroll_state = dir
    return host:isCursorUnlocked()
end

function Loam.truncate(text, max_width)
    return clamp_text(text, max_width)
end

---@param fn fun(root: LoamElement)
---@param renderer LoamRenderer
---@param inputs { mouse_pos: Vector2, mouse_state: Event.Press.state, scroll_state: -1|1 }?
---@return LoamElement, fun()[]
function Loam.build(fn, renderer, inputs)
    inputs = inputs or {}
    local mouse_pos = client.getMousePos() / client.getGuiScale()

    d = 0

    local hover_checks = list()

    local element = LoamElement.new({})
        :with(fn)
        :calculate_sizes()
        :propagate_sizes()
        :distribute_space()
        :draw_children(renderer, inputs.mouse_pos or mouse_pos, inputs.mouse_state or mouse_state, inputs.scroll_state or scroll_state, nil, nil, hover_checks)

    renderer:draw_all()

    if mouse_state == 1 then
        mouse_state = 2
    elseif (inputs.mouse_state or mouse_state) == 0 then
        held_clicking[renderer] = nil
    end

    if scroll_state ~= 0 then
        scroll_state = 0
    end

    return element, hover_checks
end

return Loam
