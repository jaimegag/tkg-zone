# Custom tags for vSphere VMs

This overlay adds the ability to specify custom tags that will be added to the created vSpehre VMs resources. 

Category/tags must exist in vCenter prior to the creation of the TKG cluster


# Usage 

Copy the `vsphere_tags_values.yaml` and the `vsphere_tags.yaml` into the `~/.config/tanzu/tkg/providers/ytt/03_customizations` folder on your workstation

Add the following property to your cluster-config.yam, updating the values with your specific tags.
Example
```
TAGS: "urn:vmomi:InventoryServiceTag:c7123c06-bb00-4fa6-a48b-b842778ff586:GLOBAL,urn:vmomi:InventoryServiceTag:c7123c06-bb00-4fa6-a48b-b842778ff586:GLOBAL"
```
You can fetch the URN for your tags using `govc tags.info <tag-name>` or `govc tags.info -c <category-name>`

Create your cluster as usual.

# Troubleshooting

If you run into a `401 Unauthorized` vCenter API error while adding the tags during the cluster creation, restart the CAPV controller to flush the local cache of sessions that CAPV maintain, that would fix the problem and allow this to work when you try to create the cluster again.