"""
Dump metadata from an MA.
"""
from perfsonar.message import psMessageBuilder, psMessageReader
from perfsonar.client import SimpleClient
from optparse import OptionParser
from lxml import etree

import logging, sys
log = logging.getLogger(__name__)

import time

def makeSNMPMAmessage():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    psm.addMetadataBlock('metadata1', 
                        subject='subject.%s' % time.time(),
                        eventType='http://ggf.org/ns/nmwg/characteristic/utilization/2.0')
    psm.addDataBlock('data1', metadataIdRef='metadata1')
    
    return psm

def makeIperfMAMessage():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    psm.addMetadataBlock('meta1',
                        subject='subject.%s' % time.time(),
                        eventType='http://ggf.org/ns/nmwg/tools/iperf/2.0')
    psm.addDataBlock('data1', metadataIdRef='meta1')
    
    return psm
    
def makeOwampMAMessage():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    psm.addMetadataBlock('meta1',
                        subject='subject.%s' % time.time(),
                        # use forceSubjectNS arg when subject ns != eventType
                        forceSubjectNS='http://ggf.org/ns/nmwg/tools/owamp/2.0/',
                        eventType='http://ggf.org/ns/nmwg/topology/2.0')
    psm.addDataBlock('data1', metadataIdRef='meta1')

    return psm

def makePingerMAMessage():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    psm.addMetadataBlock('meta1',
                        subject='subject.%s' % time.time(),
                        eventType='http://ggf.org/ns/nmwg/tools/pinger/2.0/')
    psm.addDataBlock('data1', metadataIdRef='meta1')
    return psm
    
_BUILDERS = { 
    'snmp' : makeSNMPMAmessage,
    'owamp' : makeOwampMAMessage,
    'iperf' : makeIperfMAMessage,
    'pinger'  : makePingerMAMessage,
}

def pmsg(*args):
    """Print message-level element"""
    s = ' '.join(args)
    print("  %s" % s)

def pmsg2(*args):
    """Print message-level sub-element"""
    s = ' '.join(args)
    print("    %s" % s)

def pdata(*args):
    """Print data block element."""
    s = ' '.join(args)
    print ("      %s" % s)

def pmeta(*args):
    """Print metadata block element."""
    s = ' '.join(args)
    print ("      %s" % s)

def dumpMaResults(message, listall=False):
    pmsg("Message metadata")
    pmsg2('id:', message.getMessageId())
    pmsg2('id ref:', message.getMessageIdRef())
    pmsg2('msg type:', message.getMessageType())
    pmsg('Message data:')
    NONE = 'NONE'
    for i in message.getDataBlockIds():
        pmsg2('Data block: %s' % i)
        d = message.getData(i)
        #print 'data attributes:',d.attribs
        pdata('data id:', d.id)
        data_key = d.key
        if data_key:            
            pdata('key paramid:', data_key.get('parametersid', NONE))
            pdata('key maKey:', data_key.get('maKey', NONE))
        else:
            pdata('key:',NONE)
        pdata('metadata ref:', d.attribs.get('metadataIdRef', NONE))
        pmsg2('Metadata for data block: %s' % i)
        # grab the associated metadata block
        md_ref = d.attribs.get('metadataIdRef', NONE)
        pmeta('metadata ref:', md_ref)
        md = message.getMetadata(md_ref)
        pmeta('metadata id:', md.id)
        subject = md.subject
        if subject:
            subj_id = md.subject.get('id', NONE)
            pmeta('subject id:', subj_id)
            if subj_id != NONE:
                subj_elt = md.findElementByID(subj_id)
                for child in subj_elt:
                    pmeta("subject item: %s" % etree.tostring(child))
            ignore = 'id', 'ns', 'prefix'
            for k, v in subject.items():
                if k not in ignore:
                    pmeta('subject %s: %s' % (k, v))
        else:
            pmeta('subject id:',NONE)
        pmeta('interface info:')
        for k,v in md.interface.items():
            pmeta('%s - %s' % (k,v))
        pmeta('event type:', md.eventType)
        pmeta('parameters:')
        if not md.params:
            pmeta(NONE)
        for k,v in md.params.items():
            pmeta('  %s = %s' % (k,v))
        if not listall:
            break

def main(args=None):
    if args is None:
        args = sys.argv
    usage = "%prog [options]"
    desc = ' '.join(__doc__.split())
    # -H rrdma.net.internet2.edu -p 8080 -u /perfSONAR_PS/services/snmpMA
    opts = OptionParser()
    opts.add_option("-d", action="store_true", dest="dumpall",
                    help="Dump all records to stdout "
                    "(default: just the first record)", 
                    default=False)
    opts.add_option("-H", "--host", dest="host", default='localhost',
                    help="SNMP MA hostname (default: %default)",
                    metavar="HOST")
    opts.add_option("-p", "--port", dest="port", default=8080,
                    help="Service port number (default: %default)",
                    metavar="PORT")
    opts.add_option("-u", "--uri", dest="uri", default="/",
                    help="Service URI (default: default: %default)",
                    metavar="URI")
    tk = _BUILDERS.keys()
    opts.add_option('-t', '--type', dest="type", default=tk[0],
                    help="Type of pS service. Options: " + 
                    ", ".join(tk) + " (default: %default)")
    opts.add_option("-v", action="store_true", dest="verbose",
                    help="Use verbose: logging.DEBUG", default=False)
    (options, args) = opts.parse_args()
    
    loglevel = logging.INFO
    if options.verbose:
        loglevel = logging.DEBUG
    
    logging.basicConfig(level=loglevel,
                        format="%(levelname)s [%(name)s] %(message)s")
    log = logging.getLogger("")
    # Get a psMessageBuilder object with the request message.
    if not _BUILDERS.has_key(options.type.lower()):
        print("ERROR: Bad -t/--type: %s" % options.type)
        opts.print_help()
        return 1
    request = _BUILDERS[options.type.lower()]()
    log.info(request.tostring())
    client = SimpleClient(options.host, options.port, options.uri)
    # setMessage() will accept either a Builder or Reader object
    # or a properly formatted xml string.
    client.setMessage(request)
    # Send the message and return the response in a psMessageReader
    # object.
    try:
        message = client.sendAndGetResponse()
    except Exception, err:
        log.fatal("in client.sendAndGetResponse(), %s" % err)
        return -1
    if log.isEnabledFor(logging.DEBUG):
        print "***********************"
        print message.tostring()
        print "***********************"

    dumpMaResults(message, listall=options.dumpall)
    
    return 0

if __name__ == '__main__':
    sys.exit(main())

