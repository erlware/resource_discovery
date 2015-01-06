[![Build Status](https://travis-ci.org/erlware/resource_discovery.svg?branch=master)](https://travis-ci.org/erlware/resource_discovery)

The Resource Discovery Application
==================================

### Authored by: Martin J. Logan @martinjlogan martinjlogan@erlware.org
### Many improvements by: Roman Shestakov

Manual build instructions
=========================

1. clone / build rebar from here: https://github.com/basho/rebar
2. clone project: git clone git@github.com:RomanShestakov/Resource_discovery.git
3. build the project: cd resource_discovery;make 


Overview
========

The Resource Discovery application allows you to set up smart Erlang clusters. Producers and consumers within an Erlang cluster can find eachother with no pre-configuration needed. For example lets say we have three services in a cluster of nodes:

    * Video Display Agent
    * Video Producer
    * System Logger

The Display Agent must of course be able to find a Video Producer and both the Video Producer and the Display Agent must know about the system logger. Before understanding how all that is expressed in Resource Discovery we need to get some definitions out of the way.
Definitions

Resource Discovery has 3 major types that you need to be concerned with. They are listed here.

resource_tuple() = {resource_type(), resource()}. The type of a resource followed by the actual resource. Local resource tuples are communicated to other resource discovery instances.

resource_type() = atom(). The name of a resource, how it is identified. For example a type of service that you have on the network may be identified by it's node name in which case you might have a resource type of 'my_service' of which there may be many node names representing resources such as {my_service, myservicenode@myhost}.

resource() = term(). Either a concrete resource or a reference to one like a pid().

Expressing Relationships
========================

Using these definitions we can describe the relationships that we have between our different services; the Video Display Agent, the Video Producer, and the System Logger. It is helpful to break things down into three categories. These are as follows:

    * Local Resources Tuples
    * Target Resource Types
    * Cached Resource Tuples

Local Resources Tuples contain those resources that a running Erlang node has to share with the cluster. A Video Display Agent node could make a call like what is below to express what it has to share with the network.

```
resource_discovery:add_local_resource_tuples({video_producer, node()}).
```

A Video Producer node needs to know about the System Logger instance and about all instances of Video Display Agent nodes. To express this it could make a call like what is below to express this.

```
resource_discovery:add_target_resource_types([video_display, system_logger]).
```

This indicates that the Video Producer service wants to find out about all services in the cluster of resource types video_display and system_logger.

Now we are set up for our system to obtain resource tuples from other nodes in the cluster and cache them locally. Cached Resource Tuples are those that have been discovered and are ready to be used. When each of the nodes comes up onto the network they will make one of the following calls:

```
resource_discovery:trade_resources().
```

or

```
resource_discovery:sync_resources().
```

This will communicate with all other nodes in the current network. When this function returns all Resource Tuples on the network that match the calling nodes Target Resource Types will be cached locally. Furthermore the local nodes Local Resource Tuples will be cached on all remote nodes that have specified their resource types as target resource types. trade_resources/0 accomplishes this asyncronously where as sync_resources is a blocking call which typically accomplishes a full sync before returning. After either of these calls have been made you can go about using the resources you have discovered.

To use a resource from the resource cache Resource Discovery provides a number of useful functions. The most common of these is get_resource/1. This will loop through resources in round robin fashion supplying a different resource each time it is called. There are also the rpc functions that act upon node based resources; these are rpc_call and rpc_multicall. There are other functions available for more control over the specific resources of a particular type you get. There are also functions provided for removing resources that have been found to be malfunctioning or simply not around anymore. This is up to the user of resource discovery to do at the application level.
Getting Notifications about New Resources

Sometimes when resources become available in the cluster it is desirable for an application to be notified of their presence. If you want immediate notification of new Cached Resources you can subscribe to notifications by using:

```
resource_discovery:add_callback_modules([video_send, log_send]).
```

The above call will ensure that the exported function "resource_up/1" will be called upon the caching of a new resource within the modules "video_send" and "log_send". Those functions will be called each time this happens regardless of the resource and so the resource up function should use pattern matching like that pictured below to only concern itself with the resources it needs to act upon.

```
resource_up({system_logger, Instance}) ->
  ... do stuff ...
resource_up(_DontCare) ->
    ok.
```

Getting into an Erlang Cloud
============================

Getting into an Erlang node cluster is required as a minimal bootstrap for Resource Discovery. To accomplish initial contact by pinging remote nodes already in the desired cloud the following entries should be in your Erlang config file.

```
{resource_discovery, 
  [
    {contact_nodes, [node1@mynet.com, node2@mynet.com]}    
  ]
}
```

These entries instruct resource discovery to ping node1 and node2 in order to join an Erlang cloud. At least one of the pings must succeed in order for startup to succeed. Optionally all this can be overridden at the command line with the -contact_node flag:

```
erl ... -contact_node node3@mynet.com
```

The above flag set at startup would instruct Resource Discovery to ping node3 instead of those configured in the config file. In the future a plugin scheme will be added so that other methods of bootstrapping into a cloud may be added. An easy way to get up and running for a test is to fire up the first node pointing to itself and then additional nodes pointing to the first as in the following example: (remember that "Macintosh" should be replaced with your local sname suffix)

```
erl -sname a -contact_node a@Macintosh
erl -sname b -contact_node a@Macintosh
erl -sname c -contact_node a@Macintosh
```
Overcoming network and resource failures with heartbeating
===========================================================

At times resources fail and are perhaps taken out of the store of Cached Resource Tuples by an application when it discovers the resource is no longer around. At other times networks may fail and clusters become separated. One way of overcomming all of this is to setup heartbeats from Resource Discovery. Resource discovery can be configured to heartbeat at a specified interval. This means that it will both re-ping the configured contact nodes and will run a trade_resources/0 at the specified interval. To enable this place configuration similar to what is below in you Erlang config file.

```
{resource_discovery, 
  [
    {heartbeat_frequency, 60000}    
  ]
}
```

An entry like that above tells Resource Discovery to ping on average every 60000 milliseconds (+- a random factor). An entry of 0 disables heartbeating all together and is the default if not configured.

Enjoy! Send questions of comments to erlware-questions@erlware.org or erlware-dev@erlware.org. 
