# MQTT.jl

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)][dev-docs-url]
[![Build Status][travis-badge-url]][travis-url]
[![Project Status: WIP – Initial development is in progress, but there has not yet been a stable, usable release suitable for the public.](repostatus-wip-svg)](repostatus-wip)

MQTT Client Library

This code builds a library which enables applications to connect to an MQTT broker to publish messages, and to subscribe to topics and receive published messages.

## Contents
* [Installation](#installation)
* [Testing](#testing)
* [Usage](#usage)
    * [Getting started](#getting-started)
    * [Basic example](#basic-example)
* [Limitations](#limitations)

## Installation
```julia-repl
pkg> add https://github.com/benelsen/MQTT.jl
```

```julia-repl
julia> using Pkg; Pkg.clone("https://github.com/benelsen/MQTT.jl")
```

## Usage

### Getting started
To use this library you need to follow at least these steps:
1. Define `on_message` and `on_disconnect` callback functions.
2. Create an instance of the `Client` struct and pass it your callback functions.
3. Call the connect method with your `Client` instance.
4. Exchange data with the broker through publish, subscribe and unsubscribe.
5. Disconnect from the broker. (Not strictly necessary, if you don't want to resume the session but considered good form and less likely to crash).

### Basic example
Refer to the corresponding method documentation to find more options.

```julia
using MQTT
broker = "test.mosquitto.org"

# Define the callback for receiving messages.
function on_message(topic, payload)
    @info "Received message" topic payload=String(payload)
end

function on_disconnect(reason)
    @info "disconnected" reason
end

# Instantiate a client.
client = Client(on_message, on_disconnect)

# instantiate connection options
opts = ConnectOpts(broker)

# connect
connect(client, opts)

# set retain to true so we can receive a message from the broker once we subscribe
#  to this topic.
publish(client, "jlExample", "Hello World!", retain=true)

# subscribe to the topic we sent a retained message to.
subscribe(client, ("jlExample", AT_LEAST_ONCE))

# unsubscribe from the topic
unsubscribe(client, "jlExample")

# disconnect from the broker.
# Not strictly needed as the broker will also disconnect us if the socket is closed.
# But this is considered good form and needed if you want to resume this session later.
disconnect(client)
```

## Limitations
- session state is limited
- no support auto-reconnect
- no support for automatic retransmission of PUBLISH packets
- only [MQTT 3.1.1][mqtt-spec] (Protocol Level 4) is implemented
- conformance as a client per [MQTT 3.1.1][mqtt-spec-conformance] is not tested
- 32 bit arm (e.g. Raspberry Pi) can't be tested on travis right now.
    It has been shown to work on a Raspberry Pi though.
    For all tested configurations see [build status][travis-url].

[dev-docs-url]: https://benelsen.github.io/MQTT.jl/julia1-support/

[travis-url]: https://travis-ci.org/benelsen/MQTT.jl
[travis-badge-url]: https://travis-ci.org/benelsen/MQTT.jl.svg?branch=julia1-support

[repostatus-wip]: https://www.repostatus.org/#wip
[repostatus-wip-svg]: https://www.repostatus.org/badges/latest/wip.svg

[mqtt-spec]: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/errata01/os/mqtt-v3.1.1-errata01-os-complete.html
[mqtt-spec-conformance]: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/errata01/os/mqtt-v3.1.1-errata01-os-complete.html#_Toc442180942
