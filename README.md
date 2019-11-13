# MQTT.jl

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://benelsen.github.io/MQTT.jl/julia1-support/)
[![Build Status](https://travis-ci.org/benelsen/MQTT.jl.svg?branch=julia1-support)](https://travis-ci.org/benelsen/MQTT.jl)

MQTT Client Library

This code builds a library which enables applications to connect to an MQTT broker to publish messages, and to subscribe to topics and receive published messages.

This library supports: fully asynchronous operation, file persistence

## Contents
 * [Installation](#installation)
 * [Testing](#testing)
 * [Usage](#usage)
    * [Getting started](#getting-started)
    * [Basic example](#basic-example)

## Installation
```julia-repl
pkg> add MQTT
```

```julia-repl
julia> using Pkg; Pkg.add("MQTT")
```

## Usage

### Getting started
To use this library you need to follow at least these steps:
1. Define an `on_msg` callback function.
2. Create an instance of the `Client` struct and pass it your `on_msg` function.
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
