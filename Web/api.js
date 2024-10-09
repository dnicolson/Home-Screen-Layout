export async function fetchApps() {
  const response = await fetch('/app-order');

  if (response.ok) {
    const appOrder = await response.text();
    localStorage.setItem('appOrder', appOrder);

    const apps = plist.parse(appOrder)['HBRootFolderKey']['HBFolderItemsKey'].map((item) =>
      item.HBItemTypeKey === 'Folder'
        ? {
            type: 'folder',
            id: item.HBFolderIdentifierKey,
            name: item.HBFolderNameKey,
            order: item.HBAppGridOrderKey,
            children: item.HBFolderItemsKey.map((folderItem) => ({
              type: folderItem.HBItemTypeKey.toLowerCase(),
              id: folderItem.HBAppIdentifierKey,
              name: folderItem.HBAppIdentifierKey,
              order: folderItem.HBAppGridOrderKey
            }))
          }
        : {
            type: 'application',
            id: item.HBAppIdentifierKey,
            name: item.HBAppIdentifierKey,
            order: item.HBAppGridOrderKey
          }
    );

    return apps;
  }
}

export async function fetchAppIcons(apps) {
  const iconsArray = await Promise.all(
    apps.map(async item => {
      const { image, name } = await fetchAppIcon(item.id);
      let childrenIcons = {};

      if (item.children && item.children.length > 0) {
        childrenIcons = await fetchAppIcons(item.children);
      }

      return { [item.id]: { image, name }, ...childrenIcons };
    })
  );

  return iconsArray.reduce((acc, cur) => ({ ...acc, ...cur }), {});
}

async function fetchAppIcon(bundleId) {
  const response = await fetch(`/app-info/${bundleId}`);
  if (!response.ok) {
    return { image: null, name: null };
  }

  const data = await response.json();
  const { image, name } = data;

  return { image, name };
}

export async function saveApps(items) {
  const appOrder = localStorage.getItem('appOrder');
  if (!appOrder) {
    alert('An error getting original app layout.');
    return;
  }

  const appOrderParsed = plist.parse(appOrder);
  appOrderParsed['HBRootFolderKey']['HBFolderItemsKey'] = items.map((item, index) =>
    item.type === 'folder'
      ? {
          HBItemTypeKey: 'Folder',
          HBFolderIdentifierKey: item.id,
          HBFolderNameKey: item.name,
          HBAppGridOrderKey: (index + 1) * 1000,
          HBFolderItemsKey: item.children.map((folderItem, folderIndex) => ({
            HBItemTypeKey: 'Application',
            HBAppIdentifierKey: folderItem.id,
            HBAppGridOrderKey: ((index + 1) * 10000) + (folderIndex * 1000)
          }))
        }
      : {
          HBItemTypeKey: 'Application',
          HBAppIdentifierKey: item.id,
          HBAppGridOrderKey: item.order
        }
      );

  const newAppOrder = plist.build(appOrderParsed);
  localStorage.setItem('appOrder', newAppOrder);

  try {
    const response = await fetch('/app-order', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream'
      },
      body: newAppOrder
    });

    const responseText = await response.text();

    if (response.ok) {
      alert(responseText);
    } else {
      throw new Error(responseText);
    }
  } catch (error) {
    alert('An error occurred saving the app layout:\n\n' + error);
  }
}
