from perfsonar.message import psMessageBuilder, psMessageReader
from perfsonar.client import SimpleClient
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
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(name)s: %(funcName)s : %(message)s")
                        
    snmpMA = makeSNMPMAmessage()
    #client = SimpleClient('localhost', 8080, '/')
    client = SimpleClient('rrdma.net.internet2.edu', 8080, 
                            '/perfSONAR_PS/services/snmpMA')
    client.setMessage(snmpMA)
    message = client.sendAndGetResponse()
    
    dumpMaResults(message, listall=False)
    
    #psbOwamp = makepSBMAowampMessage()
    #client = SimpleClient('ndb1.net.internet2.edu', 8085, 
    #                        '/perfSONAR_PS/services/pSB')
    #client.setMessage(psbOwamp)
    #message = client.sendAndGetResponse()
    #print message.tostring()
    #dumpResults(message)

    pass