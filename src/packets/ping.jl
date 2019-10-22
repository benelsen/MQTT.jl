struct Pingreq <: Packet
    header::UInt8
end
Pingreq() = Pingreq(UInt8(PINGREQ))
Base.show(io::IO, x::Pingreq) = print(io, "pingreq")

struct Pingresp <: Packet
    header::UInt8
end
Pingresp() = Pingresp(UInt8(PINGRESP))
Base.show(io::IO, x::Pingresp) = print(io, "pingresp")
