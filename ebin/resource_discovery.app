%%% -*- mode:erlang -*-
{application, resource_discovery,
 [
  % A quick description of the application.
  {description, "Resource discovery & management"},

  % The version of the applicaton
  {vsn, "0.2.0.0"},

  % All modules used by the application.
  {modules,
   [
    	resource_discovery,
	rd_core,
	rd_heartbeat,
	rd_store,
	rd_sup
   ]},

  % All of the registered names the application uses.
  {registered, []},

  % Applications that are to be started prior to this one.
  {applications,
   [
    kernel, 
    stdlib,
    sasl,
    fslib,
    gas
   ]},

  % configuration parameters
  {env, []},

  % The M F A to start this application.
  {mod, {resource_discovery, []}}
 ]
}.

