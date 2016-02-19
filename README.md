#RaVe
RaVe (Ruby and Vista Environment) is an implementation of a web service designed to service clients built on the [Clinical Client Platform](https://github.com/sparseware/ccp-bellavista). It leverages a Ruby web framework, built on top of [Rack](http://rack.github.io), called SIRF. SIRF is included with this project. 

Please the [BellaVista client wiki](https://github.com/sparseware/ccp-bellavista/wiki/Data-Model) for the data model that this service supports.

The environment is configured to service */hub/main/* as its REST prefix, which maps to the *vista* sub-directory in this repository. Unless otherwise specified in the *config.yml* file, this directory and subdirectories contain ruby files that map to a piece of the path in a URL. The ruby file in-turn contains a Ruby class with methods that map to another piece of the path in the URL.

The framework will locate the appropriate file and execute the appropriate method. The method is responsible for dealing with any other sub-paths and parameters.

For example, making the REST call */hub/main/patient/allergies* will invoke the allergies method in the *Patient* class defined in the file called *patient.rb*.

To add a new path, simply add a new ruby file in the directory (or a sub-directory), no other configuration is required.

**Note:** The VA VistA plugin was developed against a OpenVistA database from Circa 2010 and has not been updated with the latest software/patches.


##Requirements
JRuby 1.7+


##Getting Started

**Before you get started ensure that the VistA RPC broker is running and functional. Ensure that you can connect to the Server with the standard CPRS client.**

The best way to run this service is to install [TorqueBox](http://torquebox.org). TorqueBox is a JBoss based application server configured for running JRuby applications. It is not necessary to actually run the TorqueBox server, just having it installed gets you most of what you need. 

The first thing that is needed is to configure the service to connect to the VA Vista RPC broker. Modify the *local.yml* file and change the *host* and *port* fields to match the location of the RPC broker and the *defdiv* field to match the default Vista division to use to login. 

Next setup your JRuby environment

####Using TorqueBox
After installing TorqueBox (and noting the directory where it was installed), Install the *erubis* gem using the JRuby from the TorqueBox installation. For example, with TorqueBox v3.1.1 on a Mac you would run the following:
`/Applications/torquebox-3.1.1/jruby/bin/jruby -S gem install erubis
`

####Using Plain old JRuby
If you just want to run with just JRuby installed you will need to install the rack, json, and erubis gems using the following:

* `jruby -S gem install rack`
* `jruby -S gem install erubis`
* `jruby -S gem install json`

You may also need to install a rack compatible web server for you platform. If you are having trouble with this setup then you should use TorqueBox.

###Running the service
To run the service from the command line, fist change to the root of the rave directory. Then invoke JRuby and tell it to use *rackup*. For example with version 3.1.1 or TorqueBox on a Mac you would run the following:
`/Applications/torquebox-3.1.1/jruby/bin/jruby -S rackup -p 8082
`

The *-p 8082* tells rackup up to host the service on port 8082.You can change this to whatever you like. Rackup uses the *config.ru* file in the root directory to start the service. The *ARGV.push 'local'*in *config.ru* tells it to use the *loca.yml* configuration file. You can create different versions of the *local.yml* file and the *config.ru* file for connecting the different RPC Brokers.

If for some reason you have problems with the default web server that comes with TorqueBox, install the Puma web server and tell rackup to use it.
For example, to install use:
`/Applications/torquebox-3.1.1/jruby/bin/jruby -S gem install puma
`

For example, to use:
`/Applications/torquebox-3.1.1/jruby/bin/jruby -S rackup -p 8082 -s puma
`

With TorqueBox you can run as a service that starts automatically when the server starts and the service can be controlled by the TorqueBox administration tool. See the TorqueBox documentation for setting this up.

###Testing the service
The easiest way to test the service (and changes you make) is with the **curl** program. This program is a command line tool that lets you make web requests. Assuming you have a server running on your local machine on port 8082, you could get the default patient list using:

`curl -c cookies.txt -b cookies.txt localhost:8082/hub/main/util/patients/list -u access:verify
`
And you could get a list of patients whose last name starts with **p** using:

`curl -c cookies.txt -b cookies.txt localhost:8082/hub/main/util/patients/list/p -u access:verify
`
And you could select a patient using:

`curl -c cookies.txt -b cookies.txt localhost:8082/hub/main/util/patients/select/6 -u access:verify`

And you could get their labs in CSV format using:

`curl -c cookies.txt -b cookies.txt localhost:8082/hub/main/labs/list -u access:verify`

and you could get their labs in JSON format using:
`curl -c cookies.txt -b cookies.txt localhost:8082/hub/main/labs/list.json -u access:verify`


**Note:** In production, basic authentication support should be disabled and SSL should be used when acing the service vian any external network.

##Configuring the [BellaVista client](https://github.com/sparseware/ccp-bellavista)
To access the service via the BellVista Client:
* Log into the client using the "Local Demo" account* Tap the "Settings" button on the action bar at the top* Tap the "Manage Servers" option in the settings popup* Tap the plus (+) icon in the "Manage Servers" option (a  "&lt;new server&gt;" entry will be added to the list)* Enter a name for the server in the **Name** field (this is the name that will appear in the login dialog)* Enter the URL for the server in the **URL** field. This is the part of the URL that comes before "/hub/main". Assuming you are running the service from the command line (as described above) on port 8082 on a machine called "vista.yourcompany.com" you would enter **http://vista.yourcompany.com:8082** (use https when connecting to a secure server).
* Restart the client and choose the server from the server drop-down list.



##Discussions
For general discussions regarding the platform please join the [Clinical Client Platform (CCP) discussion group](http://groups.google.com/d/forum/clinical-client-platform)

## License
RaVe is available under the GNU Affero General Public License See the [LICENSE](LICENSE) file for more info.

##Acknowledgements

A thank you to **Steve Shreeve** for:

* Writing the original RPC broker client
* Inspiring me to use Ruby and to write the SIRF frame work


