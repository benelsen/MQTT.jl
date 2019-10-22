struct Disconnect <: Packet
    header::UInt8
end
Disconnect() = Disconnect(UInt8(DISCONNECT))
Base.show(io::IO, x::Disconnect) = print(io, "disconnect")
