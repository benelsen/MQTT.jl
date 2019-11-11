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
    # read fixed header
    header = read(s, UInt8)
    packet_type = PacketType(header & 0xF0)
    flags = header & 0x0F
    len = read_len(s)

    # read variable header and payload into buffer
    buffer = PipeBuffer(read(s, len))

    packet = read(buffer, flags, PACKETS[packet_type])
    return packet
end

function write_packet(s::IO, packet::Packet)
    # write variable header and payload to determine length
    buffer = PipeBuffer()
    write(buffer, packet)
    data = take!(buffer)

    # write fixed header
    write(s, packet.header)
    write_len(s, length(data))

    # write variable header and payload
    write(s, data)
end
