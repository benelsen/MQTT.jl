using Random, Test, MQTT, MbedTLS, Sockets

@testset "smoke test against test.mosquitto.org - TCP" begin

    condition = Condition()

    expected_topic = randstring(10)
    expected_payload = Vector{UInt8}(randstring(5))

    counter_message = 0
    counter_disconnect = 0

    function on_message(topic, payload)
        if topic == expected_topic && payload == expected_payload
            counter_message += 1
        end
        notify(condition)
    end

    function on_disconnect(reason)
        counter_disconnect += 1
    end

    client = Client(on_message, on_disconnect, 60)
    opts = ConnectOpts("test.mosquitto.org", 1883; keep_alive = 0x0006)

    @info "Testing reconnect"
    connect(client, opts)
    disconnect(client)
    # wait(condition_disconnect)
    @test counter_disconnect === 1

    connect(client, opts)

    @info "Subscribe qos 1"
    subscribe(client, (expected_topic, AT_MOST_ONCE))

    @info "Testing publish qos 0"
    publish(client, expected_topic, expected_payload, qos=AT_MOST_ONCE)
    wait(condition)
    @test counter_message === 1

    unsubscribe(client, expected_topic)


    @info "Subscribe qos 1"
    subscribe(client, (expected_topic, AT_LEAST_ONCE))

    @info "Testing publish qos 1"
    publish(client, expected_topic, expected_payload, qos=AT_LEAST_ONCE)
    wait(condition)
    @test counter_message === 2

    unsubscribe(client, expected_topic)


    @info "Subscribe qos 2"
    subscribe(client, (expected_topic, EXACTLY_ONCE))

    @info "Testing publish qos 2"
    publish(client, expected_topic, expected_payload, qos=EXACTLY_ONCE)
    wait(condition)
    @test counter_message === 3

    unsubscribe(client, expected_topic)

    sleep(1)

    disconnect(client)
    @test counter_disconnect === 2

    @test !isopen(client.io)
end

@testset "TLS over TCP" begin

    function create_ssl_socket()
        sock = Sockets.connect("test.mosquitto.org", 8883)
        ctx = MbedTLS.SSLContext()
        conf = MbedTLS.SSLConfig(false)
        MbedTLS.setup!(ctx, conf)
        MbedTLS.associate!(ctx, sock)
        MbedTLS.handshake!(ctx)
        return ctx
    end

    condition = Condition()

    expected_topic = randstring(10)
    expected_payload = Vector{UInt8}(randstring(5))

    counter_message = 0
    counter_disconnect = 0

    function on_message(topic, payload)
        if topic == expected_topic && payload == expected_payload
            counter_message += 1
        end
        notify(condition)
    end

    function on_disconnect(reason)
        counter_disconnect += 1
    end

    client = Client(on_message, on_disconnect, 60)
    opts = ConnectOpts(create_ssl_socket; client_id = randstring(10), keep_alive = 0x0006)

    @info "Testing reconnect"
    connect(client, opts)
    disconnect(client)
    # wait(condition_disconnect)
    @test counter_disconnect === 1

    connect(client, opts)

    @info "Subscribe qos 1"
    subscribe(client, (expected_topic, AT_MOST_ONCE))

    @info "Testing publish qos 0"
    publish(client, expected_topic, expected_payload, qos=AT_MOST_ONCE)
    wait(condition)
    @test counter_message === 1

    unsubscribe(client, expected_topic)


    @info "Subscribe qos 1"
    subscribe(client, (expected_topic, AT_LEAST_ONCE))

    @info "Testing publish qos 1"
    publish(client, expected_topic, expected_payload, qos=AT_LEAST_ONCE)
    wait(condition)
    @test counter_message === 2

    unsubscribe(client, expected_topic)


    @info "Subscribe qos 2"
    subscribe(client, (expected_topic, EXACTLY_ONCE))

    @info "Testing publish qos 2"
    publish(client, expected_topic, expected_payload, qos=EXACTLY_ONCE)
    wait(condition)
    @test counter_message === 3

    unsubscribe(client, expected_topic)

    sleep(1)

    disconnect(client)
    @test counter_disconnect === 2

    @test !isopen(client.io)
end
