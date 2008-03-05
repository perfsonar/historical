#!/usr/bin/env python
#
# test_PS.py
# Brian Tierney:  bltierney@es.net
#
# This script is used to  run and time a set of sample querys using the perfSONAR 
# generic client client.pl 
#
# Input: a config file with the following format
#  <perfSONAR-tests>
#    <requestDir>/path/toXML/files</requestDir>
#    <getAll>MetadataKeyRequest_getAll.xml</getAll>
#    <test>
#       <input>testfile.xml</input>
#       <description>Test description.</description>
#       <expected_output>strings to look for in result</expected_output>
#    </test>
#  </perfSONAR-tests>
#
# output: Pass/Fail messages and performance information
#
# To Do:
#   do each test 2 times, one with bad input, to test for error message
#   save timing results in a csv file for plotting
#   better implementation of verbose option
#   add ability to specify tags vs text vs attrib in config file?
#   general cleanup
#   using too many temporary files! (but helpful for debugging) Store results in memory
#
# Possible improvements:
#    verify that data returned looks right (ie: start/end times, step size, etc.)
#
import time, sys, os, string, os.path, random
from stat import *
from subprocess import *
from optparse import OptionParser
from xml.etree  import ElementTree

PSHOME = os.getenv("PSHOME")
if PSHOME == None:
    print "Error: PSHOME env variable not set"
    sys.exit(-1)

# location of client.pl
client_script = PSHOME+"/client/client.pl "

# log files for this program go here
logdir = "/tmp/"

defaultService = "http://localhost:8081/"
requestDir = "/test_harness/requests/"

# request to get list of all interfaces in the MA
getAllRequest = ""   # get this from config file

configFile = "ps-test-config.xml"

# define namespaces
NMWG = "{http://ggf.org/ns/nmwg/base/2.0/}"
NMWGT = "{http://ggf.org/ns/nmwg/topology/2.0/}"
NMWGR = "{http://ggf.org/ns/nmwg/result/2.0/}"
NMWGS = "{http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/}"

verbose = 0

#######################################################

def getOptions():
    """ add Comment here
    """
    global verbose, PSHOME
    parser = OptionParser()
    parser.add_option("-u", "--url", action="store", type="string", dest="PS_url",
                  default=defaultService,
                  help="Connect to MA and LS service at this URL [default = %default]", metavar="URL")
    parser.add_option("-m", "--MA", action="store", type="string", dest="MA_url",
                  default=None,
                  help="Connect to MA service only at this URL [default = %default]", metavar="URL")
    parser.add_option("-l", "--LS", action="store", type="string", dest="LS_url",
                  default=None,
                  help="Connect to LS service only at this URL [default = %default]", metavar="URL")
    parser.add_option("-D", "--dir", action="store", type="string", dest="requestDir",
                  default=requestDir,
                  help="Directory where XML request files are found [default = %default]", metavar="PATH")
    parser.add_option("-c", "--cfg", action="store", type="string", dest="configFile",
                  default=configFile,
                  help="Text configuration file [default = %default]", metavar="CFG")
    parser.add_option("-v", "--verbose",
                  action="store_true", dest="verbose", default=False,
                  help="print status messages to stdout [default = %default]")
    (options, args) = parser.parse_args()

    if options.verbose:
	verbose = 1
        print "\nUsing the following Settings: "
        print "   url: ", options.PS_url
        print "   MA_url: ", options.MA_url
        print "   LS_url: ", options.LS_url
        print "   Requests: ", options.requestDir
        print "   verbose: ", options.verbose
        print "\n"

    return(options)

#######################################################

def loadTestConfigFile(filename):
    """ add Comment here
    """
    global requestDir

    inputFile = []
    testDescription = []
    expectedOutput = []
    getAllRequest = ""

    tree = ElementTree.parse(filename)

    e = tree.find("//getAll")
    try:
        getAllRequest = e.text
    except:
        print "getAll not found in config file, Using default value for getAllRequest"

    e = tree.find("//requestDir")
    try:
        requestDir = PSHOME + "/" + e.text
    except:
        print "requestDir not found in config file, Using default value for requestDir"
        requestDir = PSHOME + requestDir

    for e in tree.findall("//test"):
        found_tag = 0
        for n in e:
            if n.tag == "input":
                inputFile.append(n.text)
                found_tag += 1
            if n.tag == "description":
                testDescription.append(n.text)
                found_tag += 1
            if n.tag == "expected_output":
                expectedOutput.append(n.text)
                found_tag += 1
        if found_tag < 2:  # if dont find all 3 tags, print error and exit
            print "Error: missing tag in test configuration file ", filename
            sys.exit(-1)

    num_interfaces = 0
    return inputFile, testDescription, expectedOutput, getAllRequest

#######################################################

def pickInterface(filename):
    """ add Comment here
    """
    num_interfaces = 0
    interfaceList = []
    hostList = []
    addrList = []

    try:
        tree = ElementTree.parse(filename)
    except:
        print "Error parsing reply file %s:" % filename, er
        sys.exit(-1)

    for e in tree.findall("//%sinterface" % NMWGT):
        # look at all children of this element
        found = 0
        for n in e:
            if n.tag.find("ifName") > 0:
                found += 1
                ifName = n.text
            if n.tag.find("hostName") > 0:
                found += 1
                hostName = n.text
            if n.tag.find("ifAddress") > 0:
                found += 1
                ifAddr = n.text
        if found < 3:
            #print "Warning: only found %d of the following: ifName, hostName, ifAddress" % found
            pass
        else: # only add to list of all information is there...
            addrList.append(ifAddr)
            interfaceList.append(ifName)
            hostList.append(hostName)
            num_interfaces += 1
         #   print "Adding to list: ", hostName, ifAddr, ifName

    print "Found %d interfaces" % num_interfaces
    # pick one at random
    random.seed()
    rdm = random.randint(0, num_interfaces-1)
    return (hostList[rdm], addrList[rdm], interfaceList[rdm])


#######################################################

def runClient(fd, logfile, service, requestFile):
    """ get data from perfSONAR using the client.pl script
    """

    cmd = client_script + service + " " + requestFile
    data = []
    if verbose > 0:
        print "\nCalling: %s (stderr = %s) \n" % (cmd, logfile)
    pipe = Popen(cmd, shell=True, stderr=fd, stdout=PIPE).stdout
    d1 = pipe.readlines()
    if verbose > 0:
        print "Query returned %d lines of data" % len(d1)
    if len(d1) == 0:
        MA_Error(fd,logfile)
        sys.exit(-1)
    return (d1)

#######################################################

def replaceElement(tree, tag, newval):
    """ add Comment here
    """
    searchstring = ".//%s%s/" % (NMWGT, tag)
    #print "Searching for: ", searchstring
    try:
        el = tree.findall(searchstring)[0]
    except:
#           print "%s not found " % tag
        pass
    else:
	if verbose > 0:
            print "replacing %s with %s" % (el.text, newval)
        el.text = newval
    return

#######################################################

def replaceElementAttribute(tree, tag, aname, newval):
    """ Unfortunately python 2.5s version of elementtree does not
	support xpath queries for attributes, so have to look one by one
    """
    searchstring = ".//%s%s/" % (NMWG, tag)
    try:
        el = tree.findall(searchstring)
    except:
        pass
    else:
	for e in el:
	    if e.get("name") == aname:
		if verbose > 0:
                    print "replacing %s with %s" % (e.text, newval)
                e.text = newval
#  	    else:
#  	        print "replaceElementAttribute: attr %s not found for tag %s " % (e.get("name"), tag)
    return

#######################################################

def MA_Error(fd, logfname):
    print "Error: no reply from MA"
    fd.close() # flush errors
    fd =  open(logfname)
    d = fd.readlines()
    print d[len(d)-1] # print last line of log file
    return()

#######################################################

def timeIt(*args):
    begin = time.time()
    r = args[0](*args[1:])
    print "TIMING %s: %f" % (args[0].__name__, time.time() - begin)
    return r

#######################################################

def main():

    global verbose, requestDir
    options = getOptions()
    inputFile, testDescription, expectedOutput, getAllRequest = loadTestConfigFile(options.configFile)
    #print inputFile
    #print testDescription
    #print expectedOutput

    # catch stdout of execed programs here
    logfname = "%s/%s.%d.log" % (logdir,os.path.basename(sys.argv[0]), os.getuid())
    fd = open(logfname, 'a')

    if options.LS_url == None:
	LS_service = options.PS_url + "/perfSONAR_PS/services/LS"  
    else:
	LS_service = options.LS_url

    if options.MA_url == None:
	MA_service = options.PS_url + "/perfSONAR_PS/services/snmpMA"
    else:
	MA_service = options.MA_url

    if options.MA_url != None:
	# assume that if user specifies MA_url, they *only* want to test the MA
	LS_service = None
    if options.LS_url != None:
	MA_service = None


    # 1st get list of interfaces
    rf = requestDir + "/" + getAllRequest
    print "Getting list of all Interfaces from the MA at %s using request file: %s " % (MA_service, rf)
    data = timeIt(runClient,fd,logfname,MA_service, rf)

    # save results to file
    resultFile = logdir + os.path.basename(getAllRequest) + ".reply"
    if verbose > 0:
        print "Creating reply file (%d lines of data): %s" % (len(data), resultFile)
    file = open(resultFile, "w")  # updated file with actual data
    file.writelines(data)
    file.close()


    hostName, ifAddr, ifName = pickInterface(resultFile)

    print "Using interface randomly selected interface %s:%s " % (hostName, ifName)

    save_maKey = ""   # place to store valid maKey for future tests
    testNum = total_pass = total_fail = 0
    for requestFile in inputFile:
        print "-----------------------------------------"
        print "Testing using file: ", requestFile
        rf = requestDir + "/" + requestFile
        try:
            tree = ElementTree.parse(rf)
        except:
            print "Error parsing request file %s" % rf
            sys.exit(-1)

        now = int(time.time())

        replaceElement(tree, "ifAddress", ifAddr)
        replaceElement(tree, "hostName", hostName)
        replaceElement(tree, "ifName", ifName)
        replaceElementAttribute(tree, "parameter", "startTime", "%s" % (now - (3600 * 12)) )  # 12 hrs ago
        replaceElementAttribute(tree, "parameter", "endTime", "%s" % (now - 600) )  # 10 min ago
 	if save_maKey != "":
            replaceElementAttribute(tree, "parameter", "maKey", save_maKey)

        #write out the modified XML
        testFile = logdir + os.path.basename(requestFile) + ".test"
        file = open(testFile, "w")  # updated file with actual data
        tree.write(file)
        file.close()

	if verbose > 0:
            print "Running test: %s " % testDescription[testNum]

        # HACK warning: assumes that if requestfile has the string "LS" in it,
        #   then it goes to the LS instead of the MA. Probably should specify this in the
        #   config file instead!
        if requestFile.find("LS") >= 0:
	    service = LS_service
        else:
	    service = MA_service

	if service == None:
	     break;
        data = timeIt(runClient,fd,logfname, service, testFile)
        #print "Got reply: %d lines " % len(data)
        # save results to file
        resultFile = logdir + os.path.basename(requestFile) + ".reply"
        file = open(resultFile, "w")  # updated file with actual data
        file.writelines(data)
        file.close()

        # now use xpath to make sure the reply looks OK.
        tree = ElementTree.parse(resultFile)
        # check for errors
        e = tree.find("//%seventType/" % NMWG) 
        if e != None and e.text.find("error") >= 0:
	     error = tree.find("//%sdatum/" % NMWGR).text
	     print "Got error message: ", error

        tpass = 0
        result = []
        eodict = {}   # dictionary of expected result strings
	fs = expectedOutput[testNum].split()  # list of strings to find
        for s in fs:
	    eodict[s] = "" 

	# XXX: check: probably a cleaner way to do this matching
        # first look in the 'interface' section for a match
        for e in tree.findall("//%sinterface" % NMWGT):
            for n in e: # for each tag
		tag = n.tag.split("}")[1]  # get part after namespace
                #print "Looking at %s for the following strings: %s " % (tag, expectedOutput[testNum])
                if eodict.has_key(tag):
	            #print "   Found %s in dictionary, setting value to %s" % (tag, n.text)
	            eodict[tag] = n.text  

        # next look at attributes in the 'parameter' section for a match
        for e in tree.findall("//%sparameter" % NMWG):
            tag = e.get("name")
            if tag == "maKey":
                save_maKey = e.text  # known good maKey: save this to use in a future request
            #print "Looking at %s for the following strings: %s " % (tag, expectedOutput[testNum])
            if eodict.has_key(tag):
		#print "   Found %s in dictionary" % tag
		eodict[tag] = e.text  

        # next look in the 'eventType' section for a match
        for e in tree.findall("//%seventType" % NMWG):
	    tag = e.text
            if eodict.has_key(tag):
		#print "   Found %s in dictionary" % tag
		eodict[tag] = e.text  

        # next look at the service tag names for a match
        for e in tree.findall("//%s%s" % (NMWGS, fs[0]) ):
	    tag = e.tag.split("}")[1]  # get part after namespace
            if eodict.has_key(tag):
		#print "   Found %s in dictionary" % tag
		eodict[tag] = e.text  

	found = 0
        for s in fs:  # make sure all were found
	    if eodict[s] != "":
		  found += 1
        
	#print "Found %d out of %d expected results " % (found, len(fs))
	if found == ( len(fs) ):
            tpass = 1

        if tpass == 0: # if all results not yet found, then check attributes in the 'datum' section too
            cnt = 0
            for e in tree.findall("//%sdatum" % NMWG):
                for s in fs:
                    #print "Looking for attribute: %s in %s " % (s, e.attrib)
                    aname = e.get(s)
		    if aname != None:
			#print " attribute %s found: %s" % (s, aname)
	                eodict[s] = aname

	        found = 0
                for s in fs:  # make sure all were found
	            if eodict[s] != "":
		        found += 1
	        if found == ( len(fs) ):
		    break
       
        if len(fs) > 1: 
	    print "Found %d out of %d expected results: %s " % (found, len(fs), expectedOutput[testNum])
	if found == ( len(fs) ):
             print "Test Passed! "
	     total_pass += 1
	     if verbose > 0:
	         for s in fs:
		     print "    %s = %s " % (s, eodict[s])
        else:
             print "Test Failed! "
	     total_fail += 1
	     for s in fs:
	         if eodict[s] != "":
		     print "    %s = %s " % (s, eodict[s])
	         else:
	             print "    %s not found " % s

        testNum += 1


    print "\nTotal of %d tests passed and %d tests failed. " % (total_pass, total_fail)
    print "Done."
    sys.exit(1)

if __name__ == "__main__": main()
