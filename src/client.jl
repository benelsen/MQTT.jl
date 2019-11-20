using Base.Threads
import Sockets
import Sockets: connect

struct MQTTException <: Exception
    msg::AbstractString
end

"""
    ConnectOpts(host, [port=1883]; <keyword arguments>)
    ConnectOpts(get_io; <keyword arguments>)

Create a `ConnectOpts` using the given hostname and port of the broker.

# Arguments
- `host::AbstractString`: host of the broker
- `port::Integer=1883`: port of the broker


- `get_io::Function`: function to create a new IO object (e.g. a `TCPSocket`)

# Keywords
- `username::Union{Nothing, String} = nothing`: username as a UTF-8 string
- `password::Union{Nothing, Vector{UInt8}} = nothing`: password as a vector of bytes
- `client_id::String = ""`: client id as a UTF-8 string.
    Zero-length string as an id is valid per MQTT 3.1.1 spec
- `clean_session::Bool = true`: discard any stored session and create a new one
- `keep_alive::UInt16 = 0x0000`: set maximum keep alive interval
- `will::Union{Nothing, Message} = nothing`: a `Message` containing a will

# Examples
```julia
opts = ConnectOpts(
    "localhost";
    username="myuser",
    password=Vector{UInt8}("secretpassword"),
    client_id="my_mqtt_client"
)
```
"""
mutable struct ConnectOpts
    clean_session::Bool
    keep_alive::UInt16
    client_id::String
    will::Union{Nothing, Message}
    username::Union{Nothing, String}
    password::Union{Nothing, Vector{UInt8}}
    get_io::Function

    function ConnectOpts(
        get_io::Function=() -> Sockets.TCPSocket();
        username::Union{Nothing, String}=nothing, password::Union{Nothing, Vector{UInt8}}=nothing,
        client_id::String="", clean_session::Bool=true, keep_alive::UInt16=0x0000,
        will::Union{Nothing, Message}=nothing
    )
        if sizeof(client_id) > 65535
            throw(MQTTException("Client identifier can not be longer than 65535 bytes"))
        end
        if !clean_session && client_id === ""
            throw(MQTTException("Resuming a session requires a non-zero length Client identifier"))
        end
        if !isnothing(username) && sizeof(username) > 65535
            throw(MQTTException("Username can not be longer than 65535 bytes"))
        end
        if !isnothing(password) && length(password) > 65535
            throw(MQTTException("Password can not be longer than 65535 bytes"))
        end
        new(clean_session, keep_alive, client_id, will, username, password, get_io)
    end
end

function ConnectOpts(host::AbstractString, port::Integer=1883; kwargs...)
    ConnectOpts(() -> Sockets.connect(host, port); kwargs...)
end

"""
    Client(on_message, on_disconnect, [ping_timeout=60])

The client struct is used to store state for a MQTT session

# Arguments
- `on_message::Function`: function to be called upon receiving a publish message
- `on_disconnect::Function`: function to be called when disconnected
- `ping_timeout::UInt64=60`: seconds the client waits for the PINGRESP
    after sending a PINGREQ before he disconnects
"""
mutable struct Client
    on_message::Function
    on_disconnect::Function
    ping_timeout::Int
    opts::ConnectOpts
    last_id::UInt16
    in_flight::Dict{UInt16, Future}
    queue::Channel{Tuple{Packet, Future}}
    disconnecting::Atomic{UInt8}
    last_sent::Atomic{Float64}
    last_received::Atomic{Float64}
    ping_outstanding::Atomic{UInt16}
    keep_alive_timer::Timer
    io::IO

    Client(on_message::Function, on_disconnect::Function, ping_timeout::Int=60) = new(
        on_message,
        on_disconnect,
        ping_timeout,
        ConnectOpts(),
        0x0000,
        Dict{UInt16, Future}(),
        Channel{Tuple{Packet, Future}}(60),
        Atomic{UInt8}(0x00),
        Atomic{Float64}(),
        Atomic{Float64}(),
        Atomic{UInt16}(),
        Timer(0.0, interval = 0),
        Sockets.TCPSocket())
end

function packet_id(c::Client)
    if c.last_id == typemax(UInt16)
        c.last_id = 0
    end
    c.last_id += 1
    return c.last_id
end

function complete(c::Client, id::UInt16, value=nothing)
    if id != 0
        if haskey(c.in_flight, id)
            future = c.in_flight[id]
            put!(future, value)
            delete!(c.in_flight, id)
        else
            disconnect(c, MQTTException("protocol error complete"))
        end
    end
end

"""
    get(future)

Connects the `Client` instance using the given options.
"""
function get(future::Future)
    r = fetch(future)
    if typeof(r) <: Exception
        throw(r)
    end
    return r
end

function send_packet(c::Client, packet::Packet, async::Bool=false)
    future = Future()
    put!(c.queue, (packet, future))
    if async
        future
    else
        @debug "send_packet" async packet
        get(future)
    end
end

function in_loop(c::Client)
    @debug "in started"
    try
        while true
            @debug "in wait"
            packet = read_packet(c.io)
            atomic_xchg!(c.last_received, time())
            @debug "in " packet
            handle(c, packet)
        end
    catch e
        @debug "in error"
        @debug e
        if isa(e, EOFError)
            e = MQTTException("connection lost")
        end
        disconnect(c, e)
    end
    @debug "in stopped"
end

function out_loop(c::Client)
    @debug "out started"
    try
        while true
            @debug "out wait"
            packet, future = take!(c.queue)

            # generate ids for packets that need one
            if needs_id(packet)
                id = packet_id(c)
                packet = typeof(packet)(packet, id)
            end

            # add the futures of packets that need acknowledgment to in flight
            if has_id(packet)
                c.in_flight[packet.id] = future
            end

            atomic_xchg!(c.last_sent, time())
            write_packet(c.io, packet)
            @debug "out " packet

            # complete the futures of packets that don't need acknowledgment
            if !has_id(packet)
                put!(future, 0)
            end
        end
    catch e
        @debug "out error"
        @debug e
        if isa(e, ArgumentError)
            e = MQTTException("connection lost")
        end
        disconnect(c, e)
    end
    @debug "out stopped"
end

function keep_alive_timer(c::Client)
    check_interval = (c.opts.keep_alive > 10) ? 5 : c.opts.keep_alive / 2
    @debug "keep_alive_timer" check_interval
    t = Timer(check_interval, interval = check_interval)
    waiter = Task(
        function()
            @debug "keep alive started"
            while isopen(t)
                wait(t)
                keep_alive(c)
            end
            @debug "keep alive stopped"
        end
    )
    yield(waiter)
    return t
end

function keep_alive(c::Client)
    keep_alive = c.opts.keep_alive
    now = time()
    if c.ping_outstanding[] == 0x00
        if now - c.last_sent[] >= keep_alive || now - c.last_received[] >= keep_alive
            send_packet(c, Pingreq())
            atomic_add!(c.ping_outstanding, 0x0001)
        end
    elseif c.ping_outstanding[] < 0x00
        disconnect(c, MQTTException("protocol error"))
    else
        if now - c.last_received[] >= c.ping_timeout
            disconnect(c, MQTTException("ping timed out"))
        end
    end
end

handle(c::Client, packet::Ack) = complete(c, packet.id)

function handle(c::Client, packet::Connack)
    r = packet.session_present
    if packet.return_code != 0
        r = ErrorException(connack_return_codes[packet.return_code])
    end
    complete(c, 0x0000, r)
end

function handle(c::Client, packet::Publish)
    if packet.message.qos == AT_LEAST_ONCE
        send_packet(c, Puback(packet.id), true)
    elseif packet.message.qos == EXACTLY_ONCE
        send_packet(c, Pubrec(packet.id), true)
    end
    @async c.on_message(packet.message.topic, packet.message.payload)
end

handle(c::Client, packet::Pubrec) = send_packet(c, Pubrel(packet.id), true)
handle(c::Client, packet::Pubrel) = send_packet(c, Pubcomp(packet.id), true)
handle(c::Client, packet::Pingresp) = atomic_sub!(c.ping_outstanding, 0x0001)

"""
    connect(client, opts; [async=false])

Connects to a broker using the specified options.

# Arguments
- `client::Client`: client needs to be instantiated before connecting, but can be
    reconnected using `connect`
- `opts::ConnectOpts`: connection options to be used

# Keywords
-  `async::Bool`: if `true` a `Future` is returned, therwise the function blocks until
    the client is connected or the operation failed.

See also [`get`](@ref).
"""
function connect(client::Client, opts::ConnectOpts; async::Bool=false)
    client.opts = opts
    client.io = opts.get_io()

    client.in_flight = Dict{UInt16, Future}()
    client.queue = Channel{Tuple{Packet, Future}}(client.queue.sz_max)
    atomic_xchg!(client.disconnecting, 0x00)

    @async out_loop(client)
    @async in_loop(client)
    if client.opts.keep_alive > 0x0000
        client.keep_alive_timer = keep_alive_timer(client)
    end

    send_packet(client, Connect(opts.clean_session, opts.keep_alive, opts.client_id, opts.will, opts.username, opts.password), async)
end

"""
    disconnect(client, [reason=nothing])

Disconnects the `Client` instance gracefully, shuts down the background tasks and stores session state.

# Arguments
- `client::Client`: client to disconnect
- `reason::Union{Exception,Nothing}=nothing`: reason for the disconnect
    This is forwarded to the `on_disconnect` callback
"""
function disconnect(client::Client, reason::Union{Exception,Nothing}=nothing)
    # ignore errors while disconnecting
    if client.disconnecting[] == 0x00
        atomic_xchg!(client.disconnecting, 0x01)
        close(client.keep_alive_timer)
        if !(typeof(reason) <: Exception)
            send_packet(client, Disconnect())
        end
        close(client.queue)
        Sockets.close(client.io)
        client.on_disconnect(reason)
    else
        @warn("Already disconnecting")
    end
end

"""
    subscribe(client, topics...; [async=false])
    subscribe(client, topics...; [qos=AT_MOST_ONCE], [async=false])

Subscribes the `Client` instance, provided as a parameter, to the specified topics.

# Arguments
- `client::Client`: the client to subscribe to the topics
- `topics...`: Topics to connect to.
    This can either be a list of `Tuple{String, QoS}` where the first element is a topic
    name and the second a QoS level, or a list of `String` topic names (`AT_MOST_ONCE` is implied unless otherwise specified with the `qos::QoS` keyword)

# Keywords
- `async::Bool=false`: If false the call blocks until the operation is complete
- `qos::QoS=AT_MOST_ONCE`: QoS level to subscribe with
"""
function subscribe(
    client::Client, topics::Topic...;
    async::Bool=false
)
    send_packet(client, Subscribe(collect(topics)), async)
end

function subscribe(
    client::Client, topics::AbstractString...;
    qos::QoS=AT_MOST_ONCE, async::Bool=false
)
    send_packet(client, Subscribe(collect(zip(topics, Iterators.repeated(qos)))), async)
end

"""
    unsubscribe(client, topics...; [async=false])

This method unsubscribes the `Client` instance from the specified topics.

# Arguments
- `client::Client`: the client to unsubscribe from the topics
- `topics::String...`: list of topics to unsubscribe from

# Keywords
- `async::Bool=false`: If false the call blocks until the operation is complete.
"""
function unsubscribe(
    client::Client, topics::AbstractString...;
    async::Bool=false
)
    send_packet(client, Unsubscribe(collect(topics)), async)
end

"""
    publish(client, topic, payload; <keyword arguments>)

Publishes a message to the broker connected to the `Client` instance provided as a parameter.

# Arguments
- `client::Client`: The client to send the message over.
- `topic::String`: The topic to publish on.
    Normal rules for publish topics apply so "/" are allowed but no wildcards.
- `payload::Union{String, Vector{UInt8}}`: payload to deliver.
    This should be a `Vector{UInt8}`. `String` is automatically converted.
    A zero length payload is allowed.

# Keywords
- `async::Bool=false`: If false the call blocks until the operation is complete.
- `qos::QoS=AT_MOST_ONCE`: The MQTT quality of service to use for the message.
    This has to be a QoS constant (AT_MOST_ONCE, AT_LEAST_ONCE, EXACTLY_ONCE).
- `retain::Bool=false`: Whether or not the message should be retained by the broker.
    This means the broker sends it to all clients who subscribe to this topic
"""
function publish(
    client::Client, topic::AbstractString, payload::Vector{UInt8};
    async::Bool=false, qos::QoS=AT_MOST_ONCE, retain::Bool=false
)
    send_packet(client, Publish(Message(false, qos, retain, topic, payload)), async)
end

function publish(
    client::Client, topic::AbstractString, payload::AbstractString;
    async::Bool=false, qos::QoS=AT_MOST_ONCE, retain::Bool=false
)
    publish(client, topic, Vector{UInt8}(payload); async=async, qos=qos, retain=retain)
end
