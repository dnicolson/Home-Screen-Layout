import { fetchApps, fetchAppIcons, saveApps } from './api.js';

const { h, render, Component } = preact;
const { v4 } = uuid;

class HomeScreenLayout extends Component {
    constructor() {
        super();
        this.state = {
            isLoading: true,
            items: [],
            icons: {},
            currentFolder: null,
            selectedAppIds: [],
            draggedItem: null
        };
    }

    async componentDidMount() {
        window.addEventListener('keydown', event => {
            if (event.key === 'Escape') {
                this.setState({ selectedAppIds: [], currentFolder: null });
            }
        });

        const apps = await fetchApps();
        if (!apps) {
            this.setState({ isLoading: false, items: [] });
            return;
        }
        const icons = await fetchAppIcons(apps);
        this.setState({ isLoading: false, items: apps, icons });
    }

    handleDragStart = (item) => {
        this.setState({ draggedItem: item });
    }

    handleDragEnd = () => {
        this.setState({ draggedItem: null });
    }

    handleDrop = (targetItem) => {
        const { draggedItem, items, currentFolder } = this.state;

        if (draggedItem && targetItem && draggedItem !== targetItem) {
            let newItems = structuredClone(items);
            if (currentFolder) {
                const updatedFolder = { ...currentFolder };
                const folderItems = [...updatedFolder.children];
                const draggedIndex = folderItems.indexOf(draggedItem);
                const targetIndex = folderItems.indexOf(targetItem);

                if (draggedIndex > -1 && targetIndex > -1) {
                    folderItems.splice(draggedIndex, 1);
                    folderItems.splice(targetIndex, 0, draggedItem);
                    updatedFolder.children = folderItems;

                    newItems = newItems.map(item =>
                        item.id === updatedFolder.id ? { ...updatedFolder } : { ...item }
                    );

                    this.setState({
                        items: newItems,
                        currentFolder: updatedFolder
                    });
                }
            } else {
                const draggedIndex = newItems.findIndex(item => item.id === draggedItem.id);
                const targetIndex = newItems.findIndex(item => item.id === targetItem.id);

                if (draggedIndex > -1 && targetIndex > -1) {
                    newItems.splice(draggedIndex, 1);
                    newItems.splice(targetIndex, 0, draggedItem);
                    this.setState({ items: newItems });
                }
            }
        }
    }

    handleClick = (item) => {
        const { selectedAppIds } = this.state;

        if (item.type === 'folder') {
            this.setState({ currentFolder: item, selectedAppIds: [] });
        } else {
            const appId = item.id;
            const isSelected = selectedAppIds.includes(appId);

            if (isSelected) {
                this.setState({ selectedAppIds: selectedAppIds.filter(id => id !== appId) });
            } else {
                this.setState({ selectedAppIds: [...selectedAppIds, appId] });
            }
        }
    };

    handleBack = () => {
        this.setState({ currentFolder: null, selectedAppIds: [] });
    }

    handleDeleteFolder = (e) => {
        const items = [...this.state.items];
        const newItems = items.filter(item => {
            return item.id !== this.state.currentFolder.id
        });
        this.setState({ items: newItems });
        this.handleBack();
    }

    handleNewFolder = () => {
        const items = [...this.state.items];
        const name = prompt('Folder name')
        if (!name) return;

        items.push({
            id: v4(),
            type: 'folder',
            name,
            children: []
        });

        this.setState({ items });
    }

    handleRenameFolder = () => {
        const items = [...this.state.items];
        const name = prompt('Folder name', this.state.currentFolder.name);
        if (!name) return;

        const folder = items.find(item => item.id === this.state.currentFolder.id);
        folder.name = name;

        this.setState({ items });
    }

    handleMoveTo = (e) => {
        const { currentFolder, selectedAppIds } = this.state;
        const folderId = e.target.value;
        let newItems = structuredClone(this.state.items);

        const findAndRemoveApps = (appId, items) => {
            for (const item of items) {
                if (item.id === appId) {
                    return items.splice(items.indexOf(item), 1)[0];
                }

                if (item.children) {
                    const app = item.children.find(child => child.id === appId);
                    if (app) {
                        return item.children.splice(item.children.indexOf(app), 1)[0];
                    }
                }
            }
        };

        selectedAppIds.forEach(appId => {
            const app = findAndRemoveApps(appId, newItems);

            if (folderId === '0') {
                newItems.push(app);
            } else {
                const targetFolder = newItems.find(item => item.id == String(folderId));
                if (targetFolder) {
                    targetFolder.children = [...targetFolder.children, app];
                }
            }
        });

        if (currentFolder) {
            const updatedFolder = newItems.find(item => item.id === currentFolder.id);

            this.setState({
                items: newItems,
                currentFolder: updatedFolder,
                selectedAppIds: []
            });
        } else {
            this.setState({
                items: newItems,
                selectedAppIds: []
            });
        }
    }

    handleSaveButton = () => {
        saveApps(this.state.items);
    }

    renderFolderBackground(items) {
        return items.slice(0,9).map(item =>
            h('div', {
                class: 'child application',
                style: this.state.icons[item.id] ? { backgroundImage: `url(${this.state.icons[item.id].image})` } : {},
            })
        )
    }

    renderGrid(items, className) {
        const icons = this.state.icons;
        return h('div', { class: className },
            items.map(item =>
                h('div', {
                    class: `icon ${item.type}${this.state.selectedAppIds.includes(item.id) ? ' active' : ''}`,
                    style: item.type !== 'folder' && icons[item.id] ? { backgroundImage: `url(${icons[item.id].image})` } : {},
                    draggable: true,
                    onClick: () => this.handleClick(item),
                    onDragStart:  () => this.handleDragStart(item),
                    onDragEnd: this.handleDragEnd,
                    onDragOver: e => e.preventDefault(),
                    onDragLeave: e => e.preventDefault(),
                    onDrop: () => this.handleDrop(item),
                    'data-id': item.id,
                    'data-name': item.type === 'folder' ? item.name : icons[item.id]?.name ?? item.id
                }, item.type === 'folder' ? this.renderFolderBackground(item.children) : icons[item.id] ? '' : item.name)
            )
        )
    }

    renderToolbar() {
        const { currentFolder, selectedAppIds } = this.state;
        const folders = this.state.items?.filter(item => item.type === 'folder');

        if (currentFolder) {
            folders.unshift({ id: 0, name: 'Home' });
            folders.splice(folders.indexOf(currentFolder), 1);
        }

        return h('div', { class: 'toolbar' },
            !currentFolder && h('button', { onClick: this.handleNewFolder }, 'New Folder'),
            currentFolder && h('button', { onClick: this.handleBack }, 'Back'),
            currentFolder && h('button', { onClick: this.handleDeleteFolder }, 'Delete Folder'),
            currentFolder && h('button', { onClick: this.handleRenameFolder }, 'Rename Folder'),
            selectedAppIds.length !== 0 && folders.length && h(
                'select',
                { onChange: this.handleMoveTo },
                h('option', { value: '' }, 'Move to…'),
                h('option', { value: '' }, ''),
                ...folders.map(folder => h('option', { value: folder.id }, folder.name))
            ),
            h('button', { onClick: () => this.handleSaveButton(this.state.items), class: 'right' }, 'Save')
        )
    }

    render() {
        const { isLoading, items, currentFolder } = this.state;

        if (isLoading) {
            return h('div', { class: 'loading' }, 'Loading…');
        }

        const itemsToRender = currentFolder ? currentFolder.children : items;

        return h('div', { class: 'container' },
            this.renderToolbar(),
            currentFolder
                ? h('div', { class: 'folder' },
                  h('div', { class: 'folder-name' }, currentFolder.name),
                  this.renderGrid(itemsToRender, 'grid folder')
                )
                : this.renderGrid(itemsToRender, 'grid main')
        );
    }
}

render(h(HomeScreenLayout), document.getElementById('app'));
