# -*- coding: utf-8 -*-
#
# Copyright 2013 - Noorul Islam K M
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

from tempest.common import rest_client
from tempest import config
import testtools

CONF = config.CONF


class SolumClient(rest_client.RestClient):

    def __init__(self, username, password, auth_url, tenant_name=None):
        super(SolumClient, self).__init__(username, password, auth_url,
                                          tenant_name)
        self.service = 'application_deployment'


class TestCase(testtools.TestCase):
    def setUp(self):
        super(TestCase, self).setUp()
        username = CONF.identity.username
        password = CONF.identity.password
        tenant_name = CONF.identity.tenant_name
        auth_url = CONF.identity.uri
        client_args = (username, password, auth_url, tenant_name)
        self.client = SolumClient(*client_args)