Topic = Tuple{String, QoS}
Base.show(io::IO, x::Topic) = print(io, "(", join(x, ", "), ")")

struct Subscribe <: HasId
    header::UInt8
    id::UInt16
    topics::Vector{Topic}
end
Subscribe(topics::Vector{Topic}) = Subscribe(UInt8(SUBSCRIBE) | 0x02, 0x0000, topics)
Subscribe(packet::Subscribe, id::UInt16) = Subscribe(packet.header, id, packet.topics)

function write(s::IO, packet::Subscribe)
    # variable header
    mqtt_write(s, packet.id)

    # payload
    for topic in packet.topics
        # topic filter
        mqtt_write(s, topic[1])
        # QoS
        mqtt_write(s, UInt8(topic[2]))
    end
end

Base.show(io::IO, x::Subscribe) = print(io, "subscribe[id: ", x.id, ", topics: ", join(x.topics, ", "), "]")

struct Suback <: Ack
    header::UInt8
    id::UInt16
    topic_return_codes::Vector{UInt8}
end
Suback(id, topic_return_codes) = Suback(UInt8(SUBACK), id, topic_return_codes)

# Suback Return codes
const suback_return_codes = Dict{UInt8, String}(
    0x00 => "Success - Maximum QoS 0",
    0x01 => "Success - Maximum QoS 1",
    0x02 => "Success - Maximum QoS 2",
    0x80 => "Failure",
    )

# TODO: If Pubrec and Pubrel have has_id = false, why not Suback?
# TODO: Handle return codes of Suback
function read(s::IO, ::UInt8, ::Type{Suback})
    id = mqtt_read(s, UInt16)
    topic_return_codes = take!(s)
    return Suback(id, topic_return_codes)
end

Base.show(io::IO, x::Suback) = print(io, "suback[id: ", x.id,
    ", return codes:", join(x.topic_return_codes, ", "), "]")
