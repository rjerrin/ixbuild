import sys
import os
import optparse
import unittest
import json
import requests
import logging

import hutils
from autils import (
 volumeExists, isServiceSet, 
 datasetExists, cifsShareExists
 )

import api_list as call
import unitbase

#TODO: logging, utils, etc


logger = logging.getLogger(__name__)

class TestCIFS(unitbase.TestBase):
    
    importantFile = '/usr/local/etc/smb4.conf'

    logger = logging.getLogger()

    def setUp(self):
        # add stuff after this call
        super(TestCIFS, self).setUp()

        # names 
        self.testuser = 'testuser'
        self.volumename = 'block2'
        self.datasetname = 'windataset'
        self.sharename = 'cifsshare'
        self.hostIP = self.host         # TODO: make a helper for this

        self.userpass = self.password         # use same for everything
        
        # setup operations
        self.setCIFSService()
        self.createUser()
        self.createStorage()
        self.createDataset()
        self.createCifsShare()


    def setCIFSService(self):
        '''
        TODO: move to general use once realize the best payload
        '''
        if not isServiceSet(self.host, 'cifs', self.user, self.password):
            
            payload =   { "cifs_srv_hostlookup": false  }
            url = hutils.make_url(self.host, 'services/cifs')
            
            res, text = call.post(url, self.auth, dataset = payload)
            
    
    def createUser(self):
        
        payload = {
          "bsdusr_username": self.testuser,
          "bsdusr_creategroup": "true",
          "bsdusr_uid": 1330,
          "bsdusr_full_name": "Doesnt Matter",
          "bsdusr_password": self.userpass,
        }

        if not self.userExists(self.testuser):
            url = hutils.make_url(self.host, 'account/users')
            res, text = call.post(url, self.auth, dataset = payload)
            
      

    def userExists(self, bsdusr_username):
        '''
        TODO: Use one from autils
        '''
        url = hutils.make_url(self.host, 'account/users')
        res, text = call.get(url, self.auth)
        for user in text:
            #print user['bsdusr_username']
            if user['bsdusr_username'] == bsdusr_username:
                return True


    def createStorage(self):
        payload = {
           "volume_name": self.volumename,
           "layout": [
            {
                   "vdevtype": "mirror",
                   "disks": ["da3", "da4"]
            }
                  ]
        }
        
        url = hutils.make_url(self.host, 'storage/volume/')  
 
        if not volumeExists(self.host, self.user, self.auth, self.volumename):   
            res, text = call.post(url, self.auth, payload)
        

    def createDataset(self):

        payload = { "name": self.datasetname }

        url = hutils.make_url(self.host, 'storage/volume/' + self.volumename + '/datasets/')
        if not datasetExists(self.host, self.user, self.password, self.volumename, self.datasetname):
            
            res, text = call.post(url, self.auth, payload)
         

    def createCifsShare(self):

        payload = {
          "cifs_name": self.sharename,
          "cifs_path": "/mnt/" + self.volumename + "/" + self.datasetname,
          "cifs_vfsobjects": [
              "aio_pthread", 
              "streams_xattr" ],
          }

        url = hutils.make_url(self.host, 'sharing/cifs')
        if not cifsShareExists(self.host, self.user, self.password, self.sharename):
            res, text = call.post(url, self.auth, payload)     

            

    def test_smbclient_1(self):
        '''
        Test basic cifs
        configuration: testing 
        with smbclient
        '''
        # create cifs share
        # command = "smbclient //10.5.0.171/tomsshare -U 'VM-IP171\tomford' -password abcd1234"
        command = "smbclient //" + self.host + "/" + self.sharename +  " -U '" + self.host + "\\" + self.testuser +"' + -password " + self.password
        print command
        err, out = hutils.sh(command, halt = True)
        # we are in the client now
        err, out = hutils.sh('showconnect', halt=True)
        
        err, out = hutils.sh('exit')

        if err:
          logging.error(err)
        logging.info(out)  

    def test_cifs_SMB2(self):
        '''
        other SMB protocols testing
        '''
        command = 'smbclient -U ' + self.testuser + ' -L ' + self.hostIP

if __name__ == '__main__':

    # for now, call it like
    # python testSNMP.py 'root' 'abcd1234' '10.5.0.171'
    #if len(sys.argv) > 1:
    #    TestCIFS.host = sys.argv.pop()
    #    TestCIFS.password = sys.argv.pop()
    #    TestCIFS.user = sys.argv.pop()
    unittest.main()
