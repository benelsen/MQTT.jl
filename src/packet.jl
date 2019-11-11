@enum(QoS::UInt8,
    AT_MOST_ONCE = 0x00,
    AT_LEAST_ONCE = 0x01,
    EXACTLY_ONCE = 0x02)

@enum(PacketType::UInt8,
    CONNECT = 0x10,
    CONNACK = 0x20,
    PUBLISH = 0x30,
    PUBACK = 0x40,
    PUBREC = 0x50,
    PUBREL = 0x60,
    PUBCOMP = 0x70,
    SUBSCRIBE = 0x80,
    SUBACK = 0x90,
    UNSUBSCRIBE = 0xA0,
    UNSUBACK = 0xB0,
    PINGREQ = 0xC0,
    PINGRESP = 0xD0,
    DISCONNECT = 0xE0)

abstract type Packet end
function write(s::IO, p::Packet) end
read(::IO, ::UInt8, T::Type{<: Packet}) = T()
has_id(::Packet) = false
needs_id(::Packet) = false

abstract type HasId <: Packet end
has_id(::HasId) = true
needs_id(::HasId) = true

abstract type Ack <: HasId end
write(s::IO, packet::Ack) = mqtt_write(s, packet.id)
read(s::IO, ::UInt8, T::Type{<: Ack}) = T(mqtt_read(s, UInt16))
needs_id(::Ack) = false

"""
    Message(topic, payload; [dup=false], [qos=AT_MOST_ONCE], [retain=false])

A container for a message with all required metadata.

Can be used as a last will message.

# Arguments
- `topic::String`
- `payload::Vector{UInt8}`

# Keywords
- `dup::Bool`: message is a duplicate
- `qos::QoS`: QoS level with which the message should be send
- `retain::Bool`: broker should retain the message

"""
struct Message
    dup::Bool
    qos::QoS
    retain::Bool
    topic::String
    payload::Vector{UInt8}
end

function Message(
    topic::String, payload::Vector{UInt8};
    dup=false, qos=AT_MOST_ONCE, retain=false
)
    Message(dup, qos, retain, topic, payload)
end

function Message(topic::String, payload::AbstractString; kwargs...)
    Message(topic, Vector{UInt8}(payload); kwargs...)
end

Base.show(io::IO, x::Message) = print(io, "[dup: ", x.dup,
    ", qos: ", x.qos, ", retain: ", x.retain, ", topic: ", x.topic, "]")
