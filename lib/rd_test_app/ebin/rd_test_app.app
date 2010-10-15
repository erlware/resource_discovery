%%% -*- mode:erlang -*-
{application, rd_test_app,
 [
  % A quick description of the application.
  {description, "Resource Discovery test application"},

  % The version of the applicaton
  {vsn, "0.1.0.0"},

  % All modules used by the application.
  {modules,
   [
    	rta_app,
	rta_sup,
	rta_server
   ]},

  % All of the registered names the application uses.
  {registered, []},

  % Applications that are to be started prior to this one.
  {applications,
   [
    kernel, 
    stdlib,
    gas,
    resource_discovery
   ]},

  % configuration parameters
  {env, []},

  % The M F A to start this application.
  {mod, {rta_app, []}}
 ]
}.

