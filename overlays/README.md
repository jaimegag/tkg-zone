# Custom tags for vSphere VMs

This overlay adds the ability to specify custom tags that will be added to the created vSpehre VMs resources. 

Category/tags must exist in vCenter prior to the creation of the TKG cluster


# Usage 

Copy the `vsphere_tags_values.yml` and the `vsphere_tags.yml` into the `~/.config/tanzu/tkg/providers/ytt/03_customizations` folder on your workstation

Add the following property to your cluster-config.yam, updating the values with your specific tags.
Example
```
TAGS: "urn:vmomi:InventoryServiceTag:c7123c06-bb00-4fa6-a48b-b842778ff586:GLOBAL,urn:vmomi:InventoryServiceTag:c7123c06-bb00-4fa6-a48b-b842778ff586:GLOBAL"
```
You can fetch the URN for your tags using `govc tags.info <tag-name>` or `govc tags.info -c <category-name>`

Create your cluster as usual.