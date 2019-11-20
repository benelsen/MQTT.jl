mqtt_read(s::IO, ::Type{UInt16}) = ntoh(read(s, UInt16))

function mqtt_read(s::IO, ::Type{String})
    len = mqtt_read(s, UInt16)
    return String(read(s, len))
end

mqtt_write(stream::IO, x) = write(stream, x)
mqtt_write(stream::IO, x::UInt16) = write(stream, hton(x))

function mqtt_write(stream::IO, x::String)
    mqtt_write(stream, convert(UInt16, sizeof(x)))
    write(stream, x)
end

function mqtt_write(stream::IO, x::Array{UInt8})
    mqtt_write(stream, convert(UInt16, length(x)))
    write(stream, x)
end

function write_len(s::IO, len::Int)
    while true
        b = UInt8(mod(len, 128))
        len = div(len, 128)
        if len > 0
            b = b | 0x80
        end
        write(s, b)
        if(len == 0)
            break
        end
    end
end

function read_len(s::IO)
    buf = Vector{UInt8}(undef, 1)
    multiplier = 1
    value = 0
    while true
        readbytes!(s, buf, 1; all = true)
        value += (buf[1] & 127) * multiplier
        multiplier *= 128
        if multiplier > 128 * 128 * 128
            throw(ErrorException("malformed remaining length"))
        end
        if (buf[1] & 128) == 0
            break
        end
    end
    return value
end
