package net.perfsonar.topology.client;

import static java.util.Arrays.asList;

import org.jdom.Element;

import joptsimple.OptionParser;
import joptsimple.OptionSet;

public class Invoker {
    public static void main(String[] args) throws Exception {
        // create a parser
        OptionParser parser = new OptionParser() {
            {
                acceptsAll( asList( "h", "?" ), "show help then exit" );
                accepts( "id", "domain id (\"domain.com\")" ).withRequiredArg();
                accepts( "url", "TS URL (\"http://domain.com:9999/perfSONAR_PS/services/topology\")" ).withRequiredArg();
                accepts( "help", "show extended help then exit" );
            }
        };

        OptionSet options = parser.parse( args );

        // check for help
        if ( options.has( "?" ) || options.has("h")) {
            parser.printHelpOn( System.out );
            System.exit(0);
        }
        if (!options.has( "id" ) || !options.has("url")) {
            parser.printHelpOn( System.out );
            System.exit(1);
        }

        String id   = (String) options.valueOf("id");
        String url  = (String) options.valueOf("url");

        Element domain = PSTopoPuller.pullTopology(url, id);

        PSTopoPuller.printTopology(domain);
    }
}
