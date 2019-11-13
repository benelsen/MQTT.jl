@info "Running packet tests"

function is_out_correct(filename_expected::AbstractString, actual::Channel{UInt8}, mid::UInt16)
    file_data = read_all_to_arr(filename_expected)
    actual_data = Vector{UInt8}()

    for i in file_data
      append!(actual_data, take!(actual))
    end

    mid_index = get_mid_index(file_data)
    if mid_index > 0
      buffer = PipeBuffer()
      write(buffer, mid)
      converted_mid = take!(buffer)
      file_data[mid_index] = converted_mid[2]
      file_data[mid_index+1] = converted_mid[1]
    end

    correct = true
    i = 1
    while i <= length(file_data)
      if file_data[i] != actual_data[i]
        correct = false
        break
      end
      i += 1
    end
    return correct
end

function is_out_correct(filename_expected::AbstractString, actual::Channel{UInt8})
    file = open(filename_expected, "r")
    correct = true

    correct_data = UInt8[]
    actual_data = UInt8[]

    while !eof(file)
        c = read(file, UInt8)
        a = take!(actual)

        push!(correct_data, c)
        push!(actual_data, a)

        if a != c
            correct = false
            break
        end
    end
    if !correct
        @error "data mismatch" correct_data actual_data
    end
    return correct
end

next_id(c) = c.last_id + 0x0001

@testset "mock tests" begin
    @testset "connect, sub, pub, disconect" begin

        function on_message(topic, payload)
            @test topic == "abc"
            @test String(payload) == "qwerty"
        end

        function on_disconnect(reason)
            @test reason == nothing
        end

        client = Client(on_message, on_disconnect)
        opts = ConnectOpts(() -> TestFileHandler(); client_id = "TestID")

        last_id::UInt16 = 0x0001

        @info "Testing connect"
        connect(client, opts)
        tfh::TestFileHandler = client.io
        @test is_out_correct("data/output/connect.dat", tfh.out_channel)
        # CONNACK is automatically being sent in connect call

        @info "Testing subscribe"
        subscribe(client, ("abc", AT_LEAST_ONCE), ("cba", AT_MOST_ONCE), async=true)
        @test is_out_correct("data/output/subreq.dat", tfh.out_channel, next_id(client))
        put_from_file(tfh, "data/input/suback.dat", client.last_id)

        @info "Testing unsubscribe"
        unsubscribe(client, "abc", "cba", async=true)
        @test is_out_correct("data/output/unsubreq.dat", tfh.out_channel, next_id(client))
        put_from_file(tfh, "data/input/unsuback.dat", client.last_id)

        @info "Testing receive publish QOS 0"
        put_from_file(tfh, "data/input/qos0pub.dat")

        @info "Testing receive publish QOS 1"
        put_from_file(tfh, "data/input/qos1pub.dat", last_id)
        @test is_out_correct("data/output/puback.dat", tfh.out_channel, last_id)
        #last_id += 1

        @info "Testing receive publish QOS 2"
        put_from_file(tfh, "data/input/qos2pub.dat", last_id)
        @test is_out_correct("data/output/pubrec.dat", tfh.out_channel, last_id)
        put_from_file(tfh, "data/input/pubrel.dat", last_id)
        @test is_out_correct("data/output/pubcomp.dat", tfh.out_channel, last_id)
        #last_id += 1

        @info "Testing send publish QOS 0"
        publish(client, "test1", "QOS_0", qos=AT_MOST_ONCE, async=true)
        @test is_out_correct("data/output/qos0pub.dat", tfh.out_channel)

        @info "Testing send publish QOS 1"
        publish(client, "test2", "QOS_1", qos=AT_LEAST_ONCE, async=true)
        @test is_out_correct("data/output/qos1pub.dat", tfh.out_channel, next_id(client))
        put_from_file(tfh, "data/input/puback.dat", client.last_id)

        @info "Testing send publish QOS 2"
        f = publish(client, "test3", "test", qos=EXACTLY_ONCE, async=true)
        id = next_id(client)
        @test is_out_correct("data/output/qos2pub.dat", tfh.out_channel, id)
        put_from_file(tfh, "data/input/pubrec.dat", id)
        @test is_out_correct("data/output/pubrel.dat", tfh.out_channel, id)
        put_from_file(tfh, "data/input/pubcomp.dat", id)

        get(f)

        @info "Testing disconnect"
        disconnect(client)
        @test is_out_correct("data/output/disco.dat", tfh.out_channel)
    end

    @testset "keep-alive" begin

        function on_message(topic, payload)
            @test topic == "abc"
            @test String(payload) == "qwerty"
        end

        function on_disconnect_ping(reason)
            @test reason.msg == "ping timed out"
        end

        #This has to be in it's own connect flow to not interfere with other messages
        @info "Testing keep alive with response"
        client = Client(on_message, on_disconnect_ping, 1)
        opts = ConnectOpts(() -> TestFileHandler(); client_id = "TestID", keep_alive = UInt16(1))
        connect(client, opts)
        tfh = client.io

        @test is_out_correct("data/output/connect_keep_alive1s.dat", tfh.out_channel)
        @test is_out_correct("data/output/pingreq.dat", tfh.out_channel)
        put_from_file(tfh, "data/input/pingresp.dat")

        sleep(1.1)

        @info "Testing keep alive without response"
        @test is_out_correct("data/output/pingreq.dat", tfh.out_channel)

        function on_disconnect_pingresp(reason)
            @test reason.msg == "protocol error"
        end

        @info "Testing unwanted pingresp"
        client = Client(on_message, on_disconnect_pingresp)
        opts = ConnectOpts(() -> TestFileHandler(); client_id = "TestID", keep_alive = 0x0001)
        connect(client, opts)
        tfh = client.io

        put_from_file(tfh, "data/input/pingresp.dat")
        sleep(2)
    end
end