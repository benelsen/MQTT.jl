import Base: read, write, close
import MQTT: read_len, Message
using Test, MQTT

include("mock.jl")
include("smoke.jl")
