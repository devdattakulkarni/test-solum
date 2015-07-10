# Copyright 2015 Rackspace Hosting
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

import uuid

from solum.api.handlers import handler
from solum import objects
from solum.openstack.common import log as logging


LOG = logging.getLogger(__name__)


class AppHandler(handler.Handler):
    """Fulfills a request on the app resource."""

    def get(self, id):
        """Return an app."""
        return objects.registry.App.get_by_uuid(self.context, id)

    def patch(self, id, data):
        """Update an app."""
        db_obj = objects.registry.App.get_by_uuid(self.context, id)

        data_dict = data.as_dict(objects.registry.App)
        obj_dict = db_obj.as_dict()

        # Source and workflow are a little tricky to update.
        new_source = obj_dict['source']
        new_source.update(data_dict.get('source', {}))
        data_dict['source'] = new_source

        new_wf = obj_dict['workflow_config']
        new_wf.update(data_dict.get('workflow_config', {}))
        data_dict['workflow_config'] = new_wf

        updated = objects.registry.App.update_and_save(self.context,
                                                       id, data_dict)
        return updated

    def delete(self, id):
        """Delete an existing app."""
        db_obj = objects.registry.App.get_by_uuid(self.context, id)
        db_obj.destroy(self.context)

    def create(self, data):
        """Create a new app."""
        db_obj = objects.registry.App()
        db_obj.id = str(uuid.uuid4())
        db_obj.user_id = self.context.user
        db_obj.project_id = self.context.tenant
        db_obj.deleted = False

        db_obj.name = data.get('name')
        db_obj.description = data.get('description')
        db_obj.languagepack = data.get('languagepack')
        db_obj.stack_id = data.get('stack_id')
        db_obj.ports = data.get('ports')
        db_obj.source = data.get('source')
        db_obj.workflow_config = data.get('workflow_config')
        db_obj.trigger_uuid = data.get('trigger_uuid')
        db_obj.trigger_actions = data.get('trigger_actions')
        db_obj.trust_id = data.get('trust_id')
        db_obj.trust_user = data.get('trust_user')

        db_obj.create(self.context)
        return db_obj

    def get_all(self):
        """Return all apps."""
        all_apps = objects.registry.AppList.get_all(self.context)
        return all_apps