local util = {}

---reverses the values of a given table
---@param table table
---@return table reversed
function util.reverseTable(table)
    for i = 1, #table/2, 1 do
        table[i], table[#table-i+1] = table[#table-i+1], table[i]
    end
    return table
end

---converts an integer into a table of bits
---@param integer integer
---@return table bits, integer numBytes
function util.toBits(integer)
    local bits = {}
    local numBits = math.max(1, select(2, math.frexp(integer)))
    for bit = numBits, 1, -1 do
        bits[bit] = math.fmod(integer, 2)
        integer = math.floor((integer - bits[bit]) / 2)
    end
    local numBytes = math.ceil(numBits / 7)
    return util.reverseTable(bits), numBytes
end


local intCache = {}
---converts an integer into a variable length byte-string
---@param integer any
---@return string byteString
function util.numToVarLengthInt(integer)
    integer = math.abs(integer)
    if intCache[integer] then return intCache[integer] end
    local bits, numBytes = util.toBits(integer)

    -- insert signBit into bit table
    for i = 1, (numBytes - 1) do
        i = (numBytes - i) * 7 + 1
        if i ~= 8 then
            table.insert(bits,i,1)
        else
            table.insert(bits,i,0)
        end
    end

    -- populate any empty bits withn a byte
    for i = 1, numBytes * 8 do
        i = (numBytes * 8 ) - i + 1
        if not bits[i] then
            if i % 8 ~= 0 then
                bits[i] = 0
            else
                if numBytes ~= 1 then
                    bits[i] = 1
                else
                    bits[i] = 0
                end
            end
        end
    end
    -- generate final byte-string
    local bitVal = 0
    local byteString = ""
    for i = 1, #bits do
        bitVal = bitVal + bits[i] * 2 ^ ((i - 1) % 8)
        if i % 8 == 0 then
            byteString = byteString .. string.char(bitVal)
            bitVal = 0
        end
    end

    byteString = string.reverse(byteString)

    intCache[integer] = byteString
    return byteString
end

---read a specified number of bits and return it as a table
---@param buffer Buffer
---@param numBytes integer
---@return table<integer> bits
function util.readBits(buffer,numBytes)
    local bufferPos = buffer:getPosition()
    local bits = {}
    for i = 0, (numBytes - 1) do
        buffer:setPosition(bufferPos + (numBytes - 1) - i)
        local currentVal = buffer:read()
        for bit = 0,7 do
            table.insert(bits,bit32.extract(currentVal,bit))
        end
    end
    buffer:setPosition(bufferPos + numBytes)
    return bits
end

---decodes a variable length number from a table of bits
---@param bits table<integer>
---@return integer number
function util.variableLengthBitsToNum(bits)
    local number = 0
    local power = 0
    for k,_ in ipairs(bits) do
        if not ((k) % 8 == 0) then
            number = number + (bits[k] * (2 ^ power))
            power = power + 1
        end
    end
    return number
end

---reads a veriable length integer from a buffer
---@param buffer Buffer
---@return integer number
function util.readVariableLengthInt(buffer)
    local bufferLength = buffer:getLength()
    local startPos = buffer:getPosition()
    repeat
        local val = buffer:read()
        local signBit = bit32.extract(val,7)
    until signBit == 0 or buffer:getPosition() == bufferLength
    local endPos = buffer:getPosition()
    buffer:setPosition(startPos)
    local bits = util.readBits(buffer,endPos - startPos)
    local number = util.variableLengthBitsToNum(bits)
    return number
end

return util