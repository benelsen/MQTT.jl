const PACKETS = Dict{PacketType, DataType}(
    CONNACK => Connack,
    PUBLISH => Publish,
    PUBACK => Puback,
    PUBREC => Pubrec,
    PUBREL => Pubrel,
    PUBCOMP => Pubcomp,
    SUBACK => Suback,
    UNSUBACK => Unsuback,
    PINGRESP => Pingresp)

function read_packet(s::IO)
    @debug "read_packet" bytesavailable(s)

    # read fixed header
    buf = Vector{UInt8}(undef, 1)
    rb = readbytes!(s, buf, 1)
    @debug "read_packet read bytes" rb 1
    if rb != 1
        throw(error("read $(rb) instead of $(1) bytes from io"))
    end

    packet_type = PacketType(buf[1] & 0xF0)
    flags = buf[1] & 0x0F

    len = read_len(s)
    resize!(buf, len)

    # read variable header and payload into buffer
    rb = readbytes!(s, buf, len)
    @debug "read_packet read bytes" rb len
    if rb != len
        throw(error("read $(rb) instead of $(len) bytes from io"))
    end

    packet = read(PipeBuffer(buf), flags, PACKETS[packet_type])
    return packet
end

function write_packet(s::IO, packet::Packet)
    # To support IOs that prohibit byte-by-byte methods (e.g. MbedTLS) we write packets to
    # buffers then write the whole buffer to the socket.
    out = PipeBuffer()

    # write variable header and payload to determine length
    buffer = PipeBuffer()
    write(buffer, packet)
    data = take!(buffer)

    # write fixed header
    write(out, packet.header)
    write_len(out, length(data))

    # write variable header and payload
    write(out, data)

    write(s, take!(out))
end
