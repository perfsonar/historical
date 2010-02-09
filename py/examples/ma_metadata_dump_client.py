from perfsonar.message import psMessageBuilder, psMessageReader
from perfsonar.client import SimpleClient
from optparse import OptionParser
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
    
def makepSBMAiperfMessage():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    psm.addMetadataBlock('meta1',
                        subject='subject.%s' % time.time(),
                        eventType='http://ggf.org/ns/nmwg/tools/iperf/2.0')
    psm.addDataBlock('data1', metadataIdRef='meta1')
    
    return psm
    
def makepSBMAowampMessage():
    psm = psMessageBuilder('metadataKeyRequest1', 'MetadataKeyRequest')
    psm.addMetadataBlock('meta1',
                        subject='subject.%s' % time.time(),
                        # use forceSubjectNS arg when subject ns != eventType
                        forceSubjectNS='http://ggf.org/ns/nmwg/tools/owamp/2.0/',
                        eventType='http://ggf.org/ns/nmwg/topology/2.0')
    psm.addDataBlock('data1', metadataIdRef='meta1')

    return psm
    
def dumpMaResults(message, listall=False):
    print 'id:', message.getMessageId()
    print 'id ref:', message.getMessageIdRef()
    print 'msg type:', message.getMessageType()
    
    for i in message.getDataBlockIds():
        print '======'
        d = message.getData(i)
        print 'data id:', d.id
        print 'key paramid:', d.key['parametersid']
        print 'key maKey:', d.key['maKey']
        print 'metadata ref:', d.attribs['metadataIdRef']
        print 'associated metadata:'
        # grab the associated metadata block
        md = message.getMetadata(d.attribs['metadataIdRef'])
        print '    metadata id:', md.id
        print '    metadata ref:', md.attribs['metadataIdRef']
        print '    subject id:', md.subject['id']
        print '    interface info:'
        for k,v in md.interface.items():
            print '      %s - %s' % (k,v)
        print '    event type:', md.eventType
        print '    parameters:'
        for k,v in md.params.items():
            print '      %s - %s' % (k,v)
        if not listall:
            break

if __name__ == '__main__':
    # -H rrdma.net.internet2.edu -p 8080 -u /perfSONAR_PS/services/snmpMA
    opts = OptionParser()
    opts.add_option("-H", "--host", dest="host", default='localhost',
                    help="SNMP MA hostname (default: localhost)", metavar="HOST")
    opts.add_option("-p", "--port", dest="port", default=8080,
                    help="Service port number (default: 8080)", metavar="PORT")
    opts.add_option("-u", "--uri", dest="uri",
                    help="Service URI (default: default: /)", metavar="URI")
    opts.add_option("-v", action="store_true", dest="verbose",
                    help="Use verbose: logging.DEBUG", default=False)
    opts.add_option("-d", action="store_true", dest="dumpall",
                    help="Dump all records to stdout (default: just the first record)", 
                    default=False)
    (options, args) = opts.parse_args()
    
    loglevel = logging.INFO
    if options.verbose:
        loglevel = logging.DEBUG
    
    logging.basicConfig(level=loglevel,
                        format="%(levelname)s: %(name)s: %(funcName)s : %(message)s")
    # Get a psMessageBuilder object with the request message.
    snmpMA = makeSNMPMAmessage()
    client = SimpleClient(options.host, options.port, options.uri)
    # setMessage() will accept either a Builder or Reader object
    # or a properly formatted xml string.
    client.setMessage(snmpMA)
    # Send the message and return the response in a psMessageReader
    # object.
    message = client.sendAndGetResponse()
    
    dumpMaResults(message, listall=options.dumpall)
    
    pass