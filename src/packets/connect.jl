struct Connect <: Packet
    header::UInt8
    protocol_name::String
    protocol_level::UInt8
    clean_session::Bool
    keep_alive::UInt16
    client_id::String
    will::Union{Nothing, Message}
    username::Union{Nothing, String}
    password::Union{Nothing, Array{UInt8}}
    id::UInt16
end
Connect(clean_session::Bool, keep_alive::UInt16, client_id::String, will::Union{Nothing, Message}, username::Union{Nothing, String}, password::Union{Nothing, Array{UInt8}}) = Connect(UInt8(CONNECT), "MQTT", 0x04, clean_session, keep_alive, client_id, will, username, password, 0)

function write(s::IO, packet::Connect)
    # variable header
    mqtt_write(s, packet.protocol_name)
    mqtt_write(s, packet.protocol_level)

    # connect flags
    clean_session_flag = UInt8(packet.clean_session) << 1
    will_flag = UInt8(!isnothing(packet.will)) << 2
    will_qos = (isnothing(packet.will) ? 0x00 : UInt8((packet.will).qos)) << 3
    will_retain = (isnothing(packet.will) ? 0x00 : UInt8((packet.will).retain)) << 5
    password_flag = UInt8(!isnothing(packet.password)) << 6
    username_flag = UInt8(!isnothing(packet.username)) << 7
    connect_flags = clean_session_flag | will_flag | will_qos | will_retain | username_flag | password_flag
    mqtt_write(s, connect_flags)

    mqtt_write(s, packet.keep_alive)
    # variable header end

    # payload
    mqtt_write(s, packet.client_id)
    if !isnothing(packet.will)
        mqtt_write(s, packet.will.topic)
        mqtt_write(s, packet.will.payload)
    end
    if !isnothing(packet.username)
        mqtt_write(s, packet.username)
    end
    if !isnothing(packet.password)
        mqtt_write(s, packet.password)
    end
end

has_id(::Connect) = true

Base.show(io::IO, x::Connect) = print(io, "connect[protocol_name: '", x.protocol_name, "'",
    ", protocol_level: ", x.protocol_level,
    ", clean_session: ", x.clean_session,
    ", keep_alive: ", x.keep_alive,
    ", client_id: '", x.client_id, "'",
    ", will: ", (x.will, "none"),
    ", username: ", (x.username, "none"),
    ", password: ", (x.password, "none"), "]")

struct Connack <: Packet
    header::UInt8
    session_present::Bool
    return_code::UInt8
end
Connack(session_present::Bool, return_code::UInt8) = Connack(UInt8(CONNACK), session_present, return_code)

# Connack Return codes
const connack_return_codes = Dict{UInt8, String}(
    0x00 => "Connection Accepted",
    0x01 => "Connection Refused, unacceptable protocol version",
    0x02 => "Connection Refused, identifier rejected",
    0x03 => "Connection Refused, Server unavailable",
    0x04 => "Connection Refused, bad user name or password",
    0x05 => "Connection Refused, not authorized"
    )

function read(s::IO, ::UInt8, ::Type{Connack})
    session_present = (read(s, UInt8) & 0x01) === 0x01
    return_code = read(s, UInt8)
    return Connack(session_present, return_code)
end

Base.show(io::IO, x::Connack) = print(io, "connack[session_present: ", x.session_present, ", return_code: ", x.return_code ,"]")
