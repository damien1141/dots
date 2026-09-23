import { Plugin, ItemView, WorkspaceLeaf, debounce, Notice } from 'obsidian';
import * as d3 from "d3";

const DEFAULT_NETWORK_SETTINGS : PluginSettings = {
	relevanceScoreThreshold: 0.5,
	nodeSize: 6,
	linkThickness: 0.6,
	repelForce: 450,
	linkForce: 0.4,
	linkDistance: 90,
	centerForce: 0.1,
	textFadeThreshold: 1.2,
	minLinkThickness: 0.6,
	maxLinkThickness: 1.4,
	maxLabelCharacters: 24,
	linkLabelSize: 9,
	nodeLabelSize: 9,
	connectionType: 'block',
	noteFillColor: '#ccd0d9',
	blockFillColor: '#8AB4F8'
};

interface PluginSettings {
    relevanceScoreThreshold: number;
    nodeSize: number;
    linkThickness: number;
    repelForce: number;
    linkForce: number;
    linkDistance: number;
    centerForce: number;
    textFadeThreshold: number;
    minLinkThickness: number;
    maxLinkThickness: number;
    maxLabelCharacters: number;
    linkLabelSize: number;
    nodeLabelSize: number;
	connectionType: string;
	noteFillColor: string;
	blockFillColor: string;
}

declare global {
    interface Window {
        smart_env: any;
    }
}

class ScGraphItemView extends ItemView {

	private plugin: ScGraphView;

	currentNoteKey: string;
	centralNote: any;
	centralNode: any;
	connectionType = 'block';
    isHovering: boolean;
	relevanceScoreThreshold = 0.5;
	nodeSize = 4;
	linkThickness = 0.3;
	repelForce = 400;
	linkForce = 0.4;
	linkDistance = 70;
	centerForce = 0.3;
	textFadeThreshold = 1.1;
	minScore = 1;
	maxScore = 0;
	minNodeSize = 3;
	maxNodeSize = 6;
	minLinkThickness = 0.3;
	maxLinkThickness = 0.6;
	nodeSelection: any;
	linkSelection: any;
	linkLabelSelection: any;
	labelSelection: any;
	updatingVisualization = false;
	isCtrlPressed = false;
	isAltPressed = false;
    isDragging = false;
	isChangingConnectionType = true;
    selectionBox: any;
	validatedLinks: any;
	maxLabelCharacters = 18;
	linkLabelSize = 7;
	nodeLabelSize = 6;
	blockFillColor = '#926ec9';
	noteFillColor = '#7c8594';
	startX = 0;
	startY = 0;
	nodes : any = [];
	links : any = [];
	connections : any = [];
	svgGroup: d3.Selection<SVGGElement, unknown, null, undefined> | null = null;
	svg: d3.Selection<SVGSVGElement, unknown, null, undefined> | null = null;
	dynamicScale = 1;
	centerHighlighted = false;
	simulation: any;
	dragging = false;
	highlightedNodeId = '-1';
	currentNoteChanging = false;
	isFiltering = false;
	settingsMade = false;

	// Cached DOM references for settings
	private settingsElements: Record<string, HTMLInputElement | null> = {};

    constructor(leaf: WorkspaceLeaf, plugin: ScGraphView) {
        super(leaf);
		this.currentNoteKey = '';
		this.isHovering = false;
		this.plugin = plugin;

		// Set the initial values from the loaded settings
        this.relevanceScoreThreshold = this.plugin.settings.relevanceScoreThreshold;
        this.nodeSize = this.plugin.settings.nodeSize;
        this.linkThickness = this.plugin.settings.linkThickness;
        this.repelForce = this.plugin.settings.repelForce;
        this.linkForce = this.plugin.settings.linkForce;
        this.linkDistance = this.plugin.settings.linkDistance;
        this.centerForce = this.plugin.settings.centerForce;
        this.textFadeThreshold = this.plugin.settings.textFadeThreshold;
        this.minLinkThickness = this.plugin.settings.minLinkThickness;
        this.maxLinkThickness = this.plugin.settings.maxLinkThickness;
        this.maxLabelCharacters = this.plugin.settings.maxLabelCharacters;
        this.linkLabelSize = this.plugin.settings.linkLabelSize;
        this.nodeLabelSize = this.plugin.settings.nodeLabelSize;
        this.connectionType = this.plugin.settings.connectionType;
		this.noteFillColor = this.plugin.settings.noteFillColor;
		this.blockFillColor = this.plugin.settings.blockFillColor;
    }

    getViewType(): string {
        return "smart-connections-visualizer";
    }

    getDisplayText(): string {
        return "Smart connections visualizer";
    }

    getIcon(): string {
        return "git-fork";
    }

	updateNodeAppearance() {
		this.nodeSelection.transition().duration(500)
			.attr('fill', (d: any) => d.fill)
			.attr('stroke', (d: any) => d.selected ? '#8AB4F8' : (d.highlighted ? '#589979' : 'transparent'))
			.attr('stroke-width', (d: any) => d.selected ? 2 : (d.highlighted ? 0.5 : 0))
			.attr('opacity', (d: any) => this.getNodeOpacity(d));
	}

	getNodeOpacity(d: any) {
		if (d.id === this.centralNode.id) return 1;
		if (d.selected) return 1;
		if (d.highlighted) return 0.8;
		return this.isHovering ? 0.1 : 1;
	}

    toggleNodeSelection(nodeId: string) {
		const node = this.nodeSelection.data().find((d: any) => d.id === nodeId);
		if (node) {
			node.selected = !node.selected;
			if (!node.selected) {
				node.highlighted = false;
			}
			this.updateNodeAppearance();
		}
	}

	clearSelections() {
		this.nodeSelection.each((d: any) => {
			d.selected = false;
			d.highlighted = false;
		});
		this.updateNodeAppearance();
	}

	highlightNode(node: any) {
        if (node.id === this.centralNode.id) {
            this.centerHighlighted = true;
        }

		this.highlightedNodeId = node.id;

        this.nodeSelection.each((d: any) => {
            if (d.id !== this.centralNode.id) {
                d.highlighted = (d.id === node.id || this.validatedLinks.some((link: any) =>
                    (link.source.id === node.id && link.target.id === d.id) ||
                    (link.target.id === node.id && link.source.id === d.id)));
            }
        });
        this.updateNodeAppearance();
        this.updateLinkAppearance(node);
        this.updateLabelAppearance(node);
        this.updateLinkLabelAppearance(node);
    }

	updateHighlight(d: any, node: any) {
		if (d.id !== this.centralNode.id) {
			d.highlighted = (d.id === node.id || this.validatedLinks.some((link: any) =>
				(link.source.id === node.id && link.target.id === d.id) ||
				(link.target.id === node.id && link.source.id === d.id)));
		}
	}

	updateLinkAppearance(node: any) {
		this.linkSelection.transition().duration(500)
			.attr('opacity', (d: any) => (d.source.id === node.id || d.target.id === node.id) ? 1 : 0.1);
	}

	updateLabelAppearance(node: any) {
		this.labelSelection.transition().duration(500)
			.attr('opacity', (d: any) => this.getLabelOpacity(d, node))
			.text((d: any) =>  d.id === this.highlightedNodeId ? this.formatLabel(d.name, false) : this.formatLabel(d.name, true));
	}

	getLabelOpacity(d: any, node: any) {
		if (!node) {
			return 1;
		}
		return (d.id === node.id || this.validatedLinks.some((link: any) =>
			(link.source.id === node.id && link.target.id === d.id)) || d.id == this.centralNode.id) ? 1 : 0.1;
	}

	updateLinkLabelAppearance(node: any) {
		this.linkLabelSelection.transition().duration(500)
		.attr('opacity', (d: any) => {
			return (d.source.id === node.id || d.target.id === node.id) ? 1 : 0;
		})
	}

	unhighlightNode(node : any) {
		this.highlightedNodeId = '-1';
        this.nodeSelection.each((d: any) => {
            if (d.id !== this.centralNode.id) d.highlighted = false;
        });
        this.updateNodeAppearance();
        this.resetLinkAppearance();
        this.resetLabelAppearance();
        this.resetLinkLabelAppearance();
        this.updateLabelAppearance(null);
    }

	resetLinkAppearance() {
		this.linkSelection.transition().duration(500).attr('opacity', 1);
	}

	resetLabelAppearance() {
		this.labelSelection.transition().duration(500).attr('opacity', 1)
			.text((d: any) => this.formatLabel(d.name, true));
	}

	resetLinkLabelAppearance() {
		this.linkLabelSelection.transition().duration(500).attr('opacity', 0);
	}

	formatLabel(path: string, truncate: boolean = true) {
		let label = this.extractLabel(path);
		return truncate ? this.truncateLabel(label) : label;
	}

	extractLabel(path: string) {
		let label = path;

		if (path && path.includes('#')) {
			const parts = path.split('#');
			let lastPart = parts[parts.length - 1];

			if (lastPart === '' || /^\{\d+\}$/.test(lastPart)) {
				lastPart = parts[parts.length - 2] + '#' + lastPart;
			}

			if (lastPart.includes('/')) {
				lastPart = lastPart.split('/').pop() || lastPart;
			}

			label = lastPart;

		} else if (path) {
			label = path.split('/').pop() || label;
		} else {
			return '';
		}

		label = label.replace(/[\[\]]/g, '')
             .replace(/\.[^/#]+#(?=\{\d+\}$)/, '')
             .replace(/\.[^/.]+$/, '');

		return label;
	}

	truncateLabel(label: string) {
		return label.length > this.maxLabelCharacters ? label.slice(0, this.maxLabelCharacters) + '...' : label;
	}

	get env() { return window.smart_env; }
	get smartNotes() { return window.smart_env?.smart_sources?.items; }

	async onOpen() {
		this.contentEl.createEl('h2', { text: 'Smart Visualizer' });
		this.contentEl.createEl('p', { text: 'Waiting for Smart Connections to load...' });

		this.render();
	}

	async render() {
		// Show loading state
		this.contentEl.empty();
		const loadingEl = this.contentEl.createEl('p', { text: 'Loading Smart Connections...' });

		// Wait for Smart Connections to be ready
		if (!this.env?.collections_loaded) {
			try {
				await this.waitForCollections();
			} catch {
				loadingEl.setText('Failed to load Smart Connections. Check that the Smart Connections plugin is installed and enabled.');
				return;
			}
		}

		this.contentEl.empty();

		if (!this.smartNotes || Object.keys(this.smartNotes).length === 0) {
			this.contentEl.createEl('p', { text: 'No notes found. Make sure Smart Connections has indexed your vault.' });
			return;
		}

		this.initializeVariables();
		this.setupSettingsMenu();
		this.setupSVG();
		this.addEventListeners();
		this.watchForNoteChanges();

		// Load latest active file if opening view for first time
		const currentNodeChange = this.app.workspace.getActiveFile();
		if (currentNodeChange && !this.currentNoteChanging) {
			this.currentNoteKey = currentNodeChange.path;
			this.currentNoteChanging = true;
			this.updateVisualization();
			return;
		}

		this.updateVisualization();
	}

	private async waitForCollections(maxWaitMs = 30000): Promise<void> {
		const start = Date.now();
		while (!this.env?.collections_loaded) {
			if (Date.now() - start > maxWaitMs) {
				throw new Error('Timeout waiting for Smart Connections collections');
			}
			await new Promise(resolve => setTimeout(resolve, 500));
		}
	}

	initializeVariables() {
		this.minScore = 1;
		this.maxScore = 0;
	}

	private computeDynamicScale(): number {
		const containerWidth = this.contentEl.clientWidth || this.contentEl.getBoundingClientRect().width || 900;
		const baseline = 900;
		const scale = Math.max(1, containerWidth / baseline);
		return Math.round(scale * 100) / 100;
	}

	setupSVG() {
		const width = this.contentEl.clientWidth;
		const height = this.contentEl.clientHeight;
		this.dynamicScale = this.computeDynamicScale();

		const svg = d3.select(this.contentEl)
			.append('svg')
			.attr('width', '100%')
			.attr('height', '98%')
			.attr('viewBox', `0 0 ${width} ${height}`)
			.attr('preserveAspectRatio', 'xMidYMid meet');

		const svgGroup = svg.append('g');

		svgGroup.append('g').attr('class', 'smart-connections-visualizer-links');
		svgGroup.append('g').attr('class', 'smart-connections-visualizer-node-labels');
		svgGroup.append('g').attr('class', 'smart-connections-visualizer-link-labels');
		svgGroup.append('g').attr('class', 'smart-connections-visualizer-nodes');

		this.svgGroup = svgGroup;
		this.svg = svg;

		// Attach zoom after svgGroup is assigned
		svg.call(d3.zoom()
			.scaleExtent([0.1, 10])
			.on('zoom', (event) => {
				svgGroup.attr('transform', event.transform);
				this.updateLabelOpacity(event.transform.k);
			}));
	}

	getSVGDimensions() {
		const width = this.contentEl.clientWidth || this.contentEl.getBoundingClientRect().width;
		const height = this.contentEl.clientHeight || this.contentEl.getBoundingClientRect().height;
		return { width, height };
	}

	initializeSimulation(width: number, height: number) {
		// Stop existing simulation if present
		if (this.simulation) {
			this.simulation.stop();
		}

		this.simulation = d3.forceSimulation()
			.force('center', d3.forceCenter(width / 2, height / 2).strength(this.centerForce))
			.force('charge', d3.forceManyBody().strength(-this.repelForce))
			.force('link', d3.forceLink()
                .id((d: any) => d.id)
                .distance((d: any) => this.linkDistanceScale(d.score))
                .strength(this.linkForce))
			.force('collide', d3.forceCollide().radius(this.nodeSize + 3).strength(0.7))
			.on('tick', this.simulationTickHandler.bind(this));

		 this.simulation.force('labels', this.avoidLabelCollisions.bind(this));
	}

	addEventListeners() {
		this.setupSVGEventListeners();
		this.setupKeyboardEventListeners();
	}

	setupSVGEventListeners() {
		d3.select('svg')
			.on('mousedown', this.onMouseDown.bind(this))
			.on('mousemove', this.onMouseMove.bind(this))
			.on('mouseup', this.onMouseUp.bind(this))
			.on('click', this.onSVGClick.bind(this));
	}

	onMouseDown(event: any) {
		// Reserved for future multiselect
	}

	onMouseMove(event: any) {
		// Reserved for future multiselect
	}

	onMouseUp() {
		// Reserved for future multiselect
	}

	onSVGClick(event: any) {
		if (!event.defaultPrevented && !event.ctrlKey) this.clearSelections();
	}

	setupKeyboardEventListeners() {
		document.addEventListener('keydown', this.onKeyDown.bind(this));
		document.addEventListener('keyup', this.onKeyUp.bind(this));
	}

	onKeyDown(event: KeyboardEvent) {
		if (event.key === 'Alt' || event.key === 'AltGraph') this.isAltPressed = true;
		if (event.key === 'Control') {
			this.isCtrlPressed = true;
		}
	}

	onKeyUp(event: KeyboardEvent) {
		if (event.key === 'Alt' || event.key === 'AltGraph') this.isAltPressed = false;
		if (event.key === 'Control') {
			this.isCtrlPressed = false;
		}
	}

	setupSettingsMenu() {
        const existingIcon = this.contentEl.querySelector('.smart-connections-visualizer-settings-icon');
        if (existingIcon) existingIcon.remove();

        const existingDropdownMenu = this.contentEl.querySelector('.sc-visualizer-dropdown-menu');
        if (existingDropdownMenu) existingDropdownMenu.remove();

        this.createSettingsIcon();
        this.createDropdownMenu();
        this.setupAccordionHeaders();
        this.cacheSettingsElements();
        this.setupSettingsEventListeners();
    }

	createDropdownMenu() {
		const dropdownMenu = this.contentEl.createEl('div', { cls: 'sc-visualizer-dropdown-menu' });
		this.buildDropdownMenuContent(dropdownMenu);
	}

	buildDropdownMenuContent(dropdownMenu: HTMLElement) {
		const menuHeader = dropdownMenu.createEl('div', { cls: 'smart-connections-visualizer-menu-header' });

		const refreshIcon = this.createRefreshIcon();
		refreshIcon.classList.add('smart-connections-visualizer-icon');
		refreshIcon.setAttribute('id', 'smart-connections-visualizer-refresh-icon');
		menuHeader.appendChild(refreshIcon);

		const xIcon = this.createNewXIcon();
		xIcon.classList.add('smart-connections-visualizer-icon');
		xIcon.setAttribute('id', 'smart-connections-visualizer-close-icon');
		menuHeader.appendChild(xIcon);

		this.addAccordionItem(dropdownMenu, 'Filters', this.getFiltersContent.bind(this));
		this.addAccordionItem(dropdownMenu, 'Display', this.getDisplayContent.bind(this));
		this.addAccordionItem(dropdownMenu, 'Forces', this.getForcesContent.bind(this));
	}

	addAccordionItem(parent: HTMLElement, title: string, buildContent: (parent: HTMLElement) => void) {
		const accordionItem = parent.createEl('div', { cls: 'smart-connections-visualizer-accordion-item' });
		const header = accordionItem.createEl('div', { cls: 'smart-connections-visualizer-accordion-header' });

		const arrowIcon = header.createEl('span', { cls: 'smart-connections-visualizer-arrow-icon' });
		arrowIcon.appendChild(this.createRightArrow());

		header.createEl('span', { text: title });

		const accordionContent = accordionItem.createEl('div', { cls: 'smart-connections-visualizer-accordion-content' });
		buildContent(accordionContent);
	}

	getFiltersContent(parent: HTMLElement) {
		const sliderContainer1 = parent.createEl('div', { cls: 'smart-connections-visualizer-slider-container' });
		sliderContainer1.createEl('label', {
			text: `Min relevance: ${(this.relevanceScoreThreshold * 100).toFixed(0)}%`,
			attr: { id: 'smart-connections-visualizer-scoreThresholdLabel', for: 'smart-connections-visualizer-scoreThreshold' }
		});

		const relevanceSlider = sliderContainer1.createEl('input', {
			attr: {
				type: 'range',
				id: 'smart-connections-visualizer-scoreThreshold',
				class: 'smart-connections-visualizer-slider',
				name: 'scoreThreshold',
				min: '0',
				max: '0.99',
				step: '0.01'
			}
		});
		relevanceSlider.value = this.relevanceScoreThreshold.toString();

		parent.createEl('label', { text: 'Connection type:', cls: 'smart-connections-visualizer-settings-item-content-label' });

		const radioContainer = parent.createEl('div', { cls: 'smart-connections-visualizer-radio-container' });

		const radioBlockLabel = radioContainer.createEl('label');
		const blockRadio = radioBlockLabel.createEl('input', { attr: { type: 'radio', name: 'connectionType', value: 'block' } });
		blockRadio.checked = (this.connectionType === 'block');
		radioBlockLabel.appendText(' Block');

		const radioNoteLabel = radioContainer.createEl('label');
		const noteRadio = radioNoteLabel.createEl('input', { attr: { type: 'radio', name: 'connectionType', value: 'note' } });
		noteRadio.checked = (this.connectionType === 'note');
		radioNoteLabel.appendText(' Note');

		const radioBothLabel = radioContainer.createEl('label');
		const bothRadio = radioBothLabel.createEl('input', { attr: { type: 'radio', name: 'connectionType', value: 'both' } });
		bothRadio.checked = (this.connectionType === 'both');
		radioBothLabel.appendText(' Both');
	}

	getDisplayContent(parent: HTMLElement) {
		const displaySettings = [
			{ id: 'smart-connections-visualizer-nodeSize', label: 'Node size', value: this.nodeSize, min: 1, max: 15, step: 0.01 },
			{ id: 'smart-connections-visualizer-maxLabelCharacters', label: 'Max label characters', value: this.maxLabelCharacters, min: 1, max: 50, step: 1 },
			{ id: 'smart-connections-visualizer-linkLabelSize', label: 'Link label size', value: this.linkLabelSize, min: 1, max: 15, step: 0.01 },
			{ id: 'smart-connections-visualizer-nodeLabelSize', label: 'Node label size', value: this.nodeLabelSize, min: 1, max: 26, step: 1 },
			{ id: 'smart-connections-visualizer-minLinkThickness', label: 'Min link thickness', value: this.minLinkThickness, min: 0.1, max: 10, step: 0.01 },
			{ id: 'smart-connections-visualizer-maxLinkThickness', label: 'Max link thickness', value: this.maxLinkThickness, min: 0.1, max: 10, step: 0.01 },
			{ id: 'smart-connections-visualizer-fadeThreshold', label: 'Text fade threshold', value: this.textFadeThreshold, min: 0.1, max: 10, step: 0.01 }
		];

		displaySettings.forEach(setting => {
			const sliderContainer = parent.createEl('div', { cls: 'smart-connections-visualizer-slider-container' });
			sliderContainer.createEl('label', { text: `${setting.label}: ${setting.value}`, attr: { id: `${setting.id}Label`, for: setting.id } });
			sliderContainer.createEl('input', { attr: { type: 'range', id: setting.id, class: 'smart-connections-visualizer-slider', name: setting.id, min: `${setting.min}`, max: `${setting.max}`, value: `${setting.value}`, step: `${setting.step}` } });
		});
	}

	getForcesContent(parent: HTMLElement) {
		const forcesSettings = [
			{ id: 'smart-connections-visualizer-repelForce', label: 'Repel force', value: this.repelForce, min: 0, max: 1500, step: 1 },
			{ id: 'smart-connections-visualizer-linkForce', label: 'Link force', value: this.linkForce, min: 0, max: 1, step: 0.01 },
			{ id: 'smart-connections-visualizer-linkDistance', label: 'Link distance', value: this.linkDistance, min: 10, max: 200, step: 1 }
		];

		forcesSettings.forEach(setting => {
			const sliderContainer = parent.createEl('div', { cls: 'smart-connections-visualizer-slider-container' });
			sliderContainer.createEl('label', { text: `${setting.label}: ${setting.value}`, attr: { id: `${setting.id}Label`, for: setting.id } });
			sliderContainer.createEl('input', { attr: { type: 'range', id: setting.id, class: 'smart-connections-visualizer-slider', name: setting.id, min: `${setting.min}`, max: `${setting.max}`, value: `${setting.value}`, step: `${setting.step}` } });
		});
	}

	toggleDropdownMenu() {
		const dropdownMenu = document.querySelector('.sc-visualizer-dropdown-menu') as HTMLElement;
		if (dropdownMenu) {
			dropdownMenu.classList.toggle('visible');
		} else {
			console.error('Dropdown menu element not found');
		}
	}

	setupAccordionHeaders() {
		const accordionHeaders = document.querySelectorAll('.smart-connections-visualizer-accordion-header');
		accordionHeaders.forEach(header => header.addEventListener('click', this.toggleAccordionContent.bind(this)));
	}

	toggleAccordionContent(event: any) {
		const content = event.currentTarget.nextElementSibling;
		const arrowIcon = event.currentTarget.querySelector('.smart-connections-visualizer-arrow-icon');
		if (content && arrowIcon) {
			content.classList.toggle('show');
			arrowIcon.innerHTML = '';
			arrowIcon.appendChild(content.classList.contains('show') ? this.createDropdownArrow() : this.createRightArrow());
		}
	}

	createDropdownArrow() {
		const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
		svg.setAttribute("class", "smart-connections-visualizer-dropdown-indicator");
		svg.setAttribute("viewBox", "0 0 16 16");
		svg.setAttribute("fill", "currentColor");

		const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path.setAttribute("fill-rule", "evenodd");
		path.setAttribute("d", "M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z");

		svg.appendChild(path);
		return svg;
	}

	createRightArrow() {
		const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
		svg.setAttribute("class", "smart-connections-visualizer-dropdown-indicator");
		svg.setAttribute("viewBox", "0 0 16 16");
		svg.setAttribute("fill", "currentColor");

		const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path.setAttribute("fill-rule", "evenodd");
		path.setAttribute("d", "M4.646 1.646a.5.5 0 0 1 .708 0l6 6a.5.5 0 0 1 0 .708l-6 6a.5.5 0 0 1-.708-.708L10.293 8 4.646 2.354a.5.5 0 0 1 0-.708z");

		svg.appendChild(path);
		return svg;
	}

	createSettingsIcon() {
		const settingsIcon = this.contentEl.createEl('div', {
			cls: ['smart-connections-visualizer-settings-icon'],
			attr: { 'aria-label': 'Open graph settings' }
		});

		const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
		svg.setAttribute("width", "24");
		svg.setAttribute("height", "24");
		svg.setAttribute("viewBox", "0 0 24 24");
		svg.setAttribute("fill", "none");
		svg.setAttribute("stroke", "currentColor");
		svg.setAttribute("stroke-width", "2");
		svg.setAttribute("stroke-linecap", "round");
		svg.setAttribute("stroke-linejoin", "round");
		svg.setAttribute("class", "smart-connections-visualizer-svg-icon smart-connections-visualizer-lucide-settings");

		const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path.setAttribute("d", "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z");
		svg.appendChild(path);

		const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
		circle.setAttribute("cx", "12");
		circle.setAttribute("cy", "12");
		circle.setAttribute("r", "3");
		svg.appendChild(circle);

		settingsIcon.appendChild(svg);
		settingsIcon.addEventListener('click', this.toggleDropdownMenu);
	}

	createRefreshIcon() {
		const refreshIcon = this.contentEl.createEl('div', { cls: 'smart-connections-visualizer-refresh-icon' });

		const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
		svg.setAttribute("width", "24");
		svg.setAttribute("height", "24");
		svg.setAttribute("viewBox", "0 0 24 24");
		svg.setAttribute("fill", "none");
		svg.setAttribute("stroke", "currentColor");
		svg.setAttribute("stroke-width", "2");
		svg.setAttribute("stroke-linecap", "round");
		svg.setAttribute("stroke-linejoin", "round");
		svg.setAttribute("class", "smart-connections-visualizer-svg-icon smart-connections-visualizer-lucide-rotate-ccw");

		const path1 = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path1.setAttribute("d", "M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8");
		svg.appendChild(path1);

		const path2 = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path2.setAttribute("d", "M3 3v5h5");
		svg.appendChild(path2);

		refreshIcon.appendChild(svg);
		return refreshIcon;
	}

	createNewXIcon() {
		const xIcon = this.contentEl.createEl('div', { cls: 'smart-connections-visualizer-x-icon' });

		const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
		svg.setAttribute("width", "24");
		svg.setAttribute("height", "24");
		svg.setAttribute("viewBox", "0 0 24 24");
		svg.setAttribute("fill", "none");
		svg.setAttribute("stroke", "currentColor");
		svg.setAttribute("stroke-width", "2");
		svg.setAttribute("stroke-linecap", "round");
		svg.setAttribute("stroke-linejoin", "round");
		svg.setAttribute("class", "smart-connections-visualizer-svg-icon smart-connections-visualizer-lucide-x");

		const path1 = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path1.setAttribute("d", "M18 6 6 18");
		svg.appendChild(path1);

		const path2 = document.createElementNS("http://www.w3.org/2000/svg", "path");
		path2.setAttribute("d", "m6 6 12 12");
		svg.appendChild(path2);

		xIcon.appendChild(svg);
		return xIcon;
	}

	private cacheSettingsElements() {
		this.settingsElements = {
			scoreThreshold: document.getElementById('smart-connections-visualizer-scoreThreshold') as HTMLInputElement | null,
			nodeSize: document.getElementById('smart-connections-visualizer-nodeSize') as HTMLInputElement | null,
			repelForce: document.getElementById('smart-connections-visualizer-repelForce') as HTMLInputElement | null,
			linkForce: document.getElementById('smart-connections-visualizer-linkForce') as HTMLInputElement | null,
			linkDistance: document.getElementById('smart-connections-visualizer-linkDistance') as HTMLInputElement | null,
			fadeThreshold: document.getElementById('smart-connections-visualizer-fadeThreshold') as HTMLInputElement | null,
			minLinkThickness: document.getElementById('smart-connections-visualizer-minLinkThickness') as HTMLInputElement | null,
			maxLinkThickness: document.getElementById('smart-connections-visualizer-maxLinkThickness') as HTMLInputElement | null,
			maxLabelCharacters: document.getElementById('smart-connections-visualizer-maxLabelCharacters') as HTMLInputElement | null,
			linkLabelSize: document.getElementById('smart-connections-visualizer-linkLabelSize') as HTMLInputElement | null,
			nodeLabelSize: document.getElementById('smart-connections-visualizer-nodeLabelSize') as HTMLInputElement | null,
		};
	}

	setupSettingsEventListeners() {
		const scoreThresholdSlider = this.settingsElements.scoreThreshold;
		if (scoreThresholdSlider) {
			const debouncedUpdate = debounce((event: Event) => {
				this.updateVisualization(parseFloat((event.target as HTMLInputElement).value));
			}, 500, true);
			scoreThresholdSlider.addEventListener('input', (event) => {
				this.updateScoreThreshold(event);
				debouncedUpdate(event);
			});
		}

		const nodeSizeSlider = this.settingsElements.nodeSize;
		if (nodeSizeSlider) {
			nodeSizeSlider.addEventListener('input', (event) => this.updateNodeSize(event));
		}

		const repelForceSlider = this.settingsElements.repelForce;
		if (repelForceSlider) {
			repelForceSlider.addEventListener('input', (event) => this.updateRepelForce(event));
		}

		const linkForceSlider = this.settingsElements.linkForce;
		if (linkForceSlider) {
			linkForceSlider.addEventListener('input', (event) => this.updateLinkForce(event));
		}

		const linkDistanceSlider = this.settingsElements.linkDistance;
		if (linkDistanceSlider) {
			linkDistanceSlider.addEventListener('input', (event) => this.updateLinkDistance(event));
		}

		const fadeThresholdSlider = this.settingsElements.fadeThreshold;
		if (fadeThresholdSlider) {
			fadeThresholdSlider.addEventListener('input', (event) => {
				this.updateFadeThreshold(event);
				this.updateLabelOpacity(d3.zoomTransform(d3.select('svg').node() as Element).k);
			});
		}

		const minLinkThicknessSlider = this.settingsElements.minLinkThickness;
		if (minLinkThicknessSlider) {
			minLinkThicknessSlider.addEventListener('input', (event) => this.updateMinLinkThickness(event));
		}

		const maxLinkThicknessSlider = this.settingsElements.maxLinkThickness;
		if (maxLinkThicknessSlider) {
			maxLinkThicknessSlider.addEventListener('input', (event) => this.updateMaxLinkThickness(event));
		}

		const connectionTypeRadios = document.querySelectorAll('input[name="connectionType"]');
		connectionTypeRadios.forEach(radio => radio.addEventListener('change', (event) => this.updateConnectionType(event)));

		const maxLabelCharactersSlider = this.settingsElements.maxLabelCharacters;
		if (maxLabelCharactersSlider) {
			maxLabelCharactersSlider.addEventListener('input', (event) => this.updateMaxLabelCharacters(event));
		}

		const linkLabelSizeSlider = this.settingsElements.linkLabelSize;
		if (linkLabelSizeSlider) {
			linkLabelSizeSlider.addEventListener('input', (event) => this.updateLinkLabelSize(event));
		}

		const nodeLabelSizeSlider = this.settingsElements.nodeLabelSize;
		if (nodeLabelSizeSlider) {
			nodeLabelSizeSlider.addEventListener('input', (event) => this.updateNodeLabelSize(event));
		}

		const closeIcon = document.getElementById('smart-connections-visualizer-close-icon');
		if (closeIcon) closeIcon.addEventListener('click', () => this.toggleDropdownMenu());

		const refreshIcon = document.getElementById('smart-connections-visualizer-refresh-icon');
		if (refreshIcon) refreshIcon.addEventListener('click', () => this.resetToDefault());
	}

	updateScoreThreshold(event: any) {
		const newScoreThreshold = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-scoreThresholdLabel');
		this.plugin.settings.relevanceScoreThreshold = newScoreThreshold;
        this.plugin.saveSettings();
		if (label) label.textContent = `Min relevance: ${(newScoreThreshold * 100).toFixed(0)}%`;
	}

	updateNodeSize(event: any) {
		const newNodeSize = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-nodeSizeLabel');
		if (label) label.textContent = `Node size: ${newNodeSize}`;
		this.plugin.settings.nodeSize = newNodeSize;
        this.plugin.saveSettings();
		this.nodeSize = newNodeSize;
		this.updateNodeSizes();
	}

	updateRepelForce(event: any) {
		const newRepelForce = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-repelForceLabel');
		if (label) label.textContent = `Repel force: ${newRepelForce}`;
		this.repelForce = newRepelForce;
		this.plugin.settings.repelForce = newRepelForce;
        this.plugin.saveSettings();
		this.updateSimulationForces();
	}

	updateLinkForce(event: any) {
		const newLinkForce = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-linkForceLabel');
		if (label) label.textContent = `Link force: ${newLinkForce}`;
		this.linkForce = newLinkForce;
		this.plugin.settings.linkForce = newLinkForce;
        this.plugin.saveSettings();
		this.updateSimulationForces();
	}

	updateLinkDistance(event: any) {
		const newLinkDistance = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-linkDistanceLabel');
		if (label) label.textContent = `Link distance: ${newLinkDistance}`;
		this.linkDistance = newLinkDistance;
		this.plugin.settings.linkDistance = newLinkDistance;
        this.plugin.saveSettings();
		this.updateSimulationForces();
	}

	updateFadeThreshold(event: any) {
		const newFadeThreshold = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-fadeThresholdLabel');
		if (label) label.textContent = `Text fade threshold: ${newFadeThreshold}`;
		this.textFadeThreshold = newFadeThreshold;
		this.plugin.settings.textFadeThreshold = newFadeThreshold;
        this.plugin.saveSettings();
	}

	updateMinLinkThickness(event: any) {
		const newMinLinkThickness = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-minLinkThicknessLabel');
		if (label) label.textContent = `Min link thickness: ${newMinLinkThickness}`;
		this.minLinkThickness = newMinLinkThickness;
		this.plugin.settings.minLinkThickness = newMinLinkThickness;
        this.plugin.saveSettings();
		this.updateLinkThickness();
	}

	updateMaxLinkThickness(event: any) {
		const newMaxLinkThickness = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-maxLinkThicknessLabel');
		if (label) label.textContent = `Max link thickness: ${newMaxLinkThickness}`;
		this.maxLinkThickness = newMaxLinkThickness;
        this.plugin.settings.maxLinkThickness = newMaxLinkThickness;
        this.plugin.saveSettings();
		this.updateLinkThickness();
	}

	updateConnectionType(event: any) {
		this.connectionType = event.target.value;
		this.isChangingConnectionType = true;
		this.plugin.settings.connectionType = this.connectionType;
        this.plugin.saveSettings();
		this.updateVisualization();
	}

	updateMaxLabelCharacters(event: any) {
		const newMaxLabelCharacters = parseInt(event.target.value, 10);
		const label = document.getElementById('smart-connections-visualizer-maxLabelCharactersLabel');
		if (label) label.textContent = `Max Label Characters: ${newMaxLabelCharacters}`;
		this.maxLabelCharacters = newMaxLabelCharacters;
		this.plugin.settings.maxLabelCharacters = newMaxLabelCharacters;
        this.plugin.saveSettings();
		this.updateNodeLabels();
	}

	updateLinkLabelSize(event: any) {
		const newLinkLabelSize = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-linkLabelSizeLabel');
		if (label) label.textContent = `Link Label Size: ${newLinkLabelSize}`;
		this.linkLabelSize = newLinkLabelSize;
		this.plugin.settings.linkLabelSize = newLinkLabelSize;
        this.plugin.saveSettings();
		this.updateLinkLabelSizes();
	}

	updateNodeLabelSize(event: any) {
		const newNodeLabelSize = parseFloat(event.target.value);
		const label = document.getElementById('smart-connections-visualizer-nodeLabelSizeLabel');
		if (label) label.textContent = `Node Label Size: ${newNodeLabelSize}`;
		this.nodeLabelSize = newNodeLabelSize;
		this.plugin.settings.nodeLabelSize = newNodeLabelSize;
        this.plugin.saveSettings();
		this.updateNodeLabelSizes();
	}

	setupCloseIcon() {
		const closeIcon = document.getElementById('smart-connections-visualizer-close-icon');
		if (closeIcon) closeIcon.addEventListener('click', () => this.toggleDropdownMenu());
	}

	closeDropdownMenu() {
		const dropdownMenu = document.querySelector('.sc-visualizer-dropdown-menu');
		if (dropdownMenu) dropdownMenu.classList.remove('open');
	}

	setupRefreshIcon() {
		const refreshIcon = document.getElementById('smart-connections-visualizer-refresh-icon');
		if (refreshIcon) refreshIcon.addEventListener('click', () => this.resetToDefault());
	}

	resetToDefault() {
		// Reset all values to their default
		this.relevanceScoreThreshold = DEFAULT_NETWORK_SETTINGS.relevanceScoreThreshold;
		this.nodeSize = DEFAULT_NETWORK_SETTINGS.nodeSize;
		this.linkThickness = DEFAULT_NETWORK_SETTINGS.linkThickness;
		this.repelForce = DEFAULT_NETWORK_SETTINGS.repelForce;
		this.linkForce = DEFAULT_NETWORK_SETTINGS.linkForce;
		this.linkDistance = DEFAULT_NETWORK_SETTINGS.linkDistance;
		this.centerForce = DEFAULT_NETWORK_SETTINGS.centerForce;
		this.textFadeThreshold = DEFAULT_NETWORK_SETTINGS.textFadeThreshold;
		this.minLinkThickness = DEFAULT_NETWORK_SETTINGS.minLinkThickness;
		this.maxLinkThickness = DEFAULT_NETWORK_SETTINGS.maxLinkThickness;
		this.maxLabelCharacters = DEFAULT_NETWORK_SETTINGS.maxLabelCharacters;
		this.linkLabelSize = DEFAULT_NETWORK_SETTINGS.linkLabelSize;
		this.nodeLabelSize = DEFAULT_NETWORK_SETTINGS.nodeLabelSize;
		this.connectionType = DEFAULT_NETWORK_SETTINGS.connectionType;
		this.noteFillColor = DEFAULT_NETWORK_SETTINGS.noteFillColor;
		this.blockFillColor = DEFAULT_NETWORK_SETTINGS.blockFillColor;

		// Save plugin settings
		this.plugin.settings.relevanceScoreThreshold = DEFAULT_NETWORK_SETTINGS.relevanceScoreThreshold;
		this.plugin.settings.nodeSize = DEFAULT_NETWORK_SETTINGS.nodeSize;
		this.plugin.settings.linkThickness = DEFAULT_NETWORK_SETTINGS.linkThickness;
		this.plugin.settings.repelForce = DEFAULT_NETWORK_SETTINGS.repelForce;
		this.plugin.settings.linkForce = DEFAULT_NETWORK_SETTINGS.linkForce;
		this.plugin.settings.linkDistance = DEFAULT_NETWORK_SETTINGS.linkDistance;
		this.plugin.settings.centerForce = DEFAULT_NETWORK_SETTINGS.centerForce;
		this.plugin.settings.textFadeThreshold = DEFAULT_NETWORK_SETTINGS.textFadeThreshold;
		this.plugin.settings.minLinkThickness = DEFAULT_NETWORK_SETTINGS.minLinkThickness;
		this.plugin.settings.maxLinkThickness = DEFAULT_NETWORK_SETTINGS.maxLinkThickness;
		this.plugin.settings.maxLabelCharacters = DEFAULT_NETWORK_SETTINGS.maxLabelCharacters;
		this.plugin.settings.linkLabelSize = DEFAULT_NETWORK_SETTINGS.linkLabelSize;
		this.plugin.settings.nodeLabelSize = DEFAULT_NETWORK_SETTINGS.nodeLabelSize;
		this.plugin.settings.connectionType = DEFAULT_NETWORK_SETTINGS.connectionType;
		this.plugin.settings.noteFillColor = DEFAULT_NETWORK_SETTINGS.noteFillColor;
		this.plugin.settings.blockFillColor = DEFAULT_NETWORK_SETTINGS.blockFillColor;
        this.plugin.saveSettings();

		// Update visualization
		this.updateLabelsToDefaults();
		this.updateSliders();
		this.updateNodeSizes();
		this.updateLinkThickness();
		this.updateSimulationForces();
		this.updateVisualization(this.relevanceScoreThreshold);
	}

	updateLabelsToDefaults() {
		const labels: Record<string, string> = {
			'smart-connections-visualizer-scoreThresholdLabel': `Min relevance: ${(this.relevanceScoreThreshold * 100).toFixed(0)}%`,
			'smart-connections-visualizer-nodeSizeLabel': `Node size: ${this.nodeSize}`,
			'smart-connections-visualizer-maxLabelCharactersLabel': `Max label characters: ${this.maxLabelCharacters}`,
			'smart-connections-visualizer-linkLabelSizeLabel': `Link label size: ${this.linkLabelSize}`,
			'smart-connections-visualizer-nodeLabelSizeLabel': `Node label size: ${this.nodeLabelSize}`,
			'smart-connections-visualizer-minLinkThicknessLabel': `Min link thickness: ${this.minLinkThickness}`,
			'smart-connections-visualizer-maxLinkThicknessLabel': `Max link thickness: ${this.maxLinkThickness}`,
			'smart-connections-visualizer-fadeThresholdLabel': `Text fade threshold: ${this.textFadeThreshold}`,
			'smart-connections-visualizer-repelForceLabel': `Repel force: ${this.repelForce}`,
			'smart-connections-visualizer-linkForceLabel': `Link force: ${this.linkForce}`,
			'smart-connections-visualizer-linkDistanceLabel': `Link distance: ${this.linkDistance}`
		};

		for (const [id, text] of Object.entries(labels)) {
			const label = document.getElementById(id);
			if (label) label.textContent = text;
		}
	}

	updateSliders() {
		const sliders: Record<string, number> = {
			'smart-connections-visualizer-scoreThreshold': this.relevanceScoreThreshold,
			'smart-connections-visualizer-nodeSize': this.nodeSize,
			'smart-connections-visualizer-repelForce': this.repelForce,
			'smart-connections-visualizer-linkForce': this.linkForce,
			'smart-connections-visualizer-linkDistance': this.linkDistance,
			'smart-connections-visualizer-fadeThreshold': this.textFadeThreshold,
			'smart-connections-visualizer-minLinkThickness': this.minLinkThickness,
			'smart-connections-visualizer-maxLinkThickness': this.maxLinkThickness,
			'smart-connections-visualizer-maxLabelCharacters': this.maxLabelCharacters,
			'smart-connections-visualizer-linkLabelSize': this.linkLabelSize,
			'smart-connections-visualizer-nodeLabelSize': this.nodeLabelSize,
		};

		for (const [id, value] of Object.entries(sliders)) {
			const slider = document.getElementById(id) as HTMLInputElement | null;
			if (slider) slider.value = `${value}`;
		}
	}

	watchForNoteChanges() {
		this.app.workspace.on('file-open', (file) => {
			if (file && this.currentNoteKey !== file.path && !this.isHovering) {
				this.currentNoteKey = file.path;
				this.currentNoteChanging = true;
				this.updateVisualization();
			}
		});
	}

	async updateVisualization(newScoreThreshold?: number) {
		if (this.updatingVisualization && !this.isChangingConnectionType) {
			this.currentNoteChanging = false;
			return;
		}

		this.isChangingConnectionType = false;

		if (newScoreThreshold !== undefined) {
			this.relevanceScoreThreshold = newScoreThreshold;
		}

		await this.updateConnections();

		const filteredConnections = this.connections.filter((connection: any) => connection.score >= this.relevanceScoreThreshold);
		const visibleNodes = new Set<string>();
		filteredConnections.forEach((connection: any) => {
			visibleNodes.add(connection.source);
			visibleNodes.add(connection.target);
		});
		visibleNodes.add(this.centralNote.key);
		const nodesData = Array.from(visibleNodes).map((id: any) => {
			const node = this.nodes.find((node: any) => node.id === id);
			return node ? node : null;
		}).filter(Boolean);

		 if (!nodesData.some((node: any) => node.id === this.centralNote.key)) {
			const centralNode = this.nodes.find((node: any) => node.id === this.centralNote.key);
			if (centralNode) {
				nodesData.push(centralNode);
			}
		}

		 nodesData.forEach((node: any) => {
			if (!node.x || !node.y) {
				node.x = Math.random() * 1000;
				node.y = Math.random() * 1000;
			}
		});

		this.validatedLinks = filteredConnections.filter((link: any) => {
			const sourceNode = nodesData.find((node: any) => node.id === link.source);
			const targetNode = nodesData.find((node: any) => node.id === link.target);
			return sourceNode && targetNode;
		});

		if (nodesData.length === 0 || this.validatedLinks.length === 0) {
			this.updatingVisualization = false;
			new Notice('No nodes or links to display after filtering. Adjust filter settings');

			 if (this.svgGroup) {
				this.nodeSelection = this.svgGroup.select('g.smart-connections-visualizer-nodes').selectAll('circle').data([]).exit().remove();
				this.linkSelection = this.svgGroup.select('g.smart-connections-visualizer-links').selectAll('line').data([]).exit().remove();
				this.linkLabelSelection = this.svgGroup.select('g.smart-connections-visualizer-link-labels').selectAll('text').data([]).exit().remove();
				this.labelSelection = this.svgGroup.select('g.smart-connections-visualizer-node-labels').selectAll('text').data([]).exit().remove();
			 }
			return;
		}

		this.updateNodeAndLinkSelection(nodesData);

		if (!this.simulation || this.currentNoteChanging || this.isFiltering) {
			const { width, height } = this.getSVGDimensions();
			this.initializeSimulation(width, height);
			this.currentNoteChanging = false;
			this.isFiltering = false;
		}

		this.simulation.nodes(nodesData).on('tick', this.simulationTickHandler.bind(this));
		this.simulation.force('link').links(this.validatedLinks)
		.distance((d: any) => this.linkDistanceScale(d.score));

		this.simulation.alpha(1).restart();

		setTimeout(() => {
			this.simulation.alphaTarget(0);
		}, 1000);

		this.updatingVisualization = false;
	}

	simulationTickHandler() {
		this.nodeSelection.attr('cx', (d: any) => d.x).attr('cy', (d: any) => d.y).style('cursor', 'pointer');
		this.linkSelection.attr('x1', (d: any) => d.source.x || 0).attr('y1', (d: any) => d.source.y || 0).style('cursor', 'pointer')
			.attr('x2', (d: any) => d.target.x || 0).attr('y2', (d: any) => d.target.y || 0);
		this.linkLabelSelection.attr('x', (d: any) => ((d.source.x + d.target.x) / 2))
			.attr('y', (d: any) => ((d.source.y + d.target.y) / 2));
		this.labelSelection
			.attr('x', (d: any) => d.x)
			.attr('y', (d: any) => d.y);
	}

	async updateConnections() {
		this.nodes = [];
		this.links = [];
		this.connections = [];
		this.minScore = 1;
		this.maxScore = 0;
		if (!this.currentNoteKey) return;
		this.centralNote = this.smartNotes[this.currentNoteKey];

		   const connections = await this.centralNote.find_connections();
		   const noteConnections = connections.filter(
			   (connection: any) => connection.score >= this.relevanceScoreThreshold
		   );
		this.addCentralNode();
		this.addFilteredConnections(noteConnections);
		const isValid = this.validateGraphData(this.nodes, this.links);
		if (!isValid) console.error('Graph data validation failed.');
	}

	addCentralNode() {
		if (this.centralNote.key && this.centralNote.key.trim() !== '' && !this.nodes.some((node: { id: any; }) => node.id === this.centralNote.key)) {
			if (!this.svg) return;
			const svg = this.svg.node() as SVGSVGElement;
			const { width, height } = svg.getBoundingClientRect();

			this.nodes.push({
				id: this.centralNote.key,
				name: this.centralNote.key,
				group: 'note',
				x: width / 2,
				y: height / 2,
				fx: null,
				fy: null,
				fill: this.noteFillColor,
				selected: false,
				highlighted: false
			});
			this.centralNode = this.nodes[this.nodes.length - 1];
		} else {
			console.error(`Central node not found or already exists: ${this.centralNote.key}`);
		}
	}

	addFilteredConnections(noteConnections: any) {
		const filteredConnections = noteConnections.filter((connection: any) => {
			if (this.connectionType === 'both') {
				return true;
			} else {
				const isBlock = connection.item?.collection_key === 'smart_blocks';
				return (this.connectionType === 'block') === isBlock;
			}
		});

		filteredConnections.forEach((connection: any, index: any) => {
			if (connection && connection.item && connection.item.key) {
				const connectionId = connection.item.key;
				this.addConnectionNode(connectionId, connection);
				this.addConnectionLink(connectionId, connection);
			} else {
				console.warn(`Skipping invalid connection at index ${index}:`, connection);
			}
		});
	}

	addConnectionNode(connectionId: any, connection: any) {
		if (!this.nodes.some((node: { id: string; }) => node.id === connectionId)) {
			const isBlock = connection.item?.collection_key === 'smart_blocks';
			this.nodes.push({
				id: connectionId,
				name: connectionId,
				group: isBlock ? 'block' : 'note',
				x: Math.random() * 1000,
				y: Math.random() * 1000,
				fx: null,
				fy: null,
				fill: isBlock ? this.blockFillColor : this.noteFillColor,
				selected: false,
				highlighted: false
			});
		}
	}

	addConnectionLink(connectionId: string, connection: any) {
		const sourceNode = this.nodes.find((node: { id: string; }) => node.id === this.centralNote.key);
		const targetNode = this.nodes.find((node: { id: string; }) => node.id === connectionId);

		if (!sourceNode || !targetNode) return;

		this.links.push({
			source: this.centralNote.key,
			target: connectionId,
			value: connection.score || 0
		});
		this.connections.push({
			source: this.centralNote.key,
			target: connectionId,
			score: connection.score || 0
		});
		this.updateScoreRange(connection.score);
	}

	updateScoreRange(score: number) {
		if (score > this.maxScore) this.maxScore = score;
		if (score < this.minScore) this.minScore = score;
	}

	validateGraphData(nodes: any[], links: any[]): boolean {
		const nodeIds = new Set(nodes.map(node => node.id));
		let isValid = true;
		links.forEach((link, index) => {
			if (!nodeIds.has(link.source)) {
				console.error(`Link at index ${index} has an invalid source: ${link.source}`);
				isValid = false;
			}
			if (!nodeIds.has(link.target)) {
				console.error(`Link at index ${index} has an invalid target: ${link.target}`);
				isValid = false;
			}
		});
		nodes.forEach((node, index) => {
			if (!node.hasOwnProperty('id') || !node.hasOwnProperty('name') || !node.hasOwnProperty('group')) {
				console.error(`Node at index ${index} is missing required properties: ${JSON.stringify(node)}`);
				isValid = false;
			}
		});
		return isValid;
	}

	updateNodeAndLinkSelection(nodesData: any) {
		const svgGroup = this.svgGroup;
		if (!svgGroup) return;

		 this.linkSelection = svgGroup.select('g.smart-connections-visualizer-links').selectAll('line')
		 .data(this.validatedLinks, (d: any) => `${d.source}-${d.target}`)
		 .join(
			 enter => this.enterLink(enter),
			 update => this.updateLink(update),
			 exit => exit.remove()
		 );


		 this.linkLabelSelection = svgGroup.select('g.smart-connections-visualizer-link-labels').selectAll('text')
        .data(this.validatedLinks, (d: any) => `${d.source.id}-${d.target.id}`)
        .join(
            enter => this.enterLinkLabel(enter),
            update => this.updateLinkLabel(update),
            exit => exit.remove()
        );

		this.labelSelection = svgGroup.select('g.smart-connections-visualizer-node-labels').selectAll('text')
			.data(nodesData, (d: any) => d.id)
			.join(
				enter => this.enterLabel(enter),
				update => this.updateLabel(update),
				exit => exit.remove()
			);

		this.nodeSelection = svgGroup.select('g.smart-connections-visualizer-nodes').selectAll('circle')
			.data(nodesData, (d: any) => d.id)
			.join(
				enter => this.enterNode(enter),
				update => this.updateNode(update),
				exit => exit.remove()
			);
	}

	enterNode(enter: any) {
		const nodeSize = this.nodeSize * this.dynamicScale;
		return enter.append('circle')
			.attr('class', 'smart-connections-visualizer-node')
			.attr('r', (d: any) => d.id === this.centralNode.id ? nodeSize + 3 : nodeSize)
			.attr('fill', (d: any) => d.fill)
			.attr('stroke', (d: any) => d.selected ? '#8AB4F8' : 'transparent')
			.attr('stroke-width', (d: any) => d.selected ? 2 : 0.3)
			.attr('opacity', 1)
			.attr('cursor', 'pointer')
			.call(d3.drag().on('start', this.onDragStart.bind(this))
				.on('drag', this.onDrag.bind(this))
				.on('end', this.onDragEnd.bind(this)))
			.on('click', this.onNodeClick.bind(this))
			.on('mouseover', this.onNodeMouseOver.bind(this))
			.on('mouseout', this.onNodeMouseOut.bind(this));
	}

	updateNode(update: any) {
		const nodeSize = this.nodeSize * this.dynamicScale;
		return update.attr('r', (d: any) => d.id === this.centralNode.id ? nodeSize + 3 : nodeSize)
			.attr('fill', (d: any) => d.selected ? '#8AB4F8' : d.fill)
			.attr('stroke', (d: any) => d.selected ? '#8AB4F8' : 'transparent')
			.attr('stroke-width', (d: any) => d.selected ? 2 : 0.3);
	}

	onDragStart(event: any, d: any) {
		if (!event.active) this.simulation.alphaTarget(0.3).restart();
		this.dragging = true;
		d.fx = d.x;
		d.fy = d.y;
	}

	onDrag(event: any, d: any) {
		if (this.isHovering) this.isHovering = false;
		d.fx = event.x;
		d.fy = event.y;
	}

	onDragEnd(event: any, d: any) {
		if (!event.active) this.simulation.alphaTarget(0);
		d.fx = null;
		d.fy = null;
		this.dragging = false;
	}

	onNodeClick(event: any, d: any) {
		if (d.id === this.centralNode.id) return;
		this.env.plugin.open_note(d.id, event);
	}

	onNodeMouseOver(event: any, d: any) {
		if (this.dragging) return;
		if (d.id === this.centralNode.id) return;

		this.isHovering = true;
		this.highlightNode(d);
		this.updateLinkLabelAppearance(d);

		this.app.workspace.trigger("hover-link", {
			event,
			source: 'D3',
			hoverParent: event.currentTarget.parentElement,
			targetEl: event.currentTarget,
			linktext: d.id,
		});
	}

	onNodeMouseOut(event: any, d: any) {
		if (this.dragging) return;

		this.isHovering = false;
		this.centerHighlighted = false;
		this.unhighlightNode(d);
		this.updateLinkLabelAppearance({ id: null });
	}

	updateLinkLabelPositions() {
		this.linkLabelSelection
			.attr('x', (d: any) => (d.source.x + d.target.x) / 2)
			.attr('y', (d: any) => (d.source.y + d.target.y) / 2);
	}

	enterLink(enter: any) {
		return enter.append('line')
			.attr('class', 'smart-connections-visualizer-link')
			.attr('stroke', '#ccd0d9')
			.attr('stroke-width', (d: any) => this.getLinkStrokeWidth(d))
			.attr('stroke-opacity', 1)
			.attr('opacity', 1);
	}

	updateLink(update: any) {
		return update.attr('stroke', '#ccd0d9')
			.attr('stroke-width', (d: any) => this.getLinkStrokeWidth(d));
	}

	getLinkStrokeWidth(d: any) {
		const minWidth = this.minLinkThickness * this.dynamicScale;
		const maxWidth = this.maxLinkThickness * this.dynamicScale;
		return d3.scaleLinear()
			.domain([this.minScore, this.maxScore])
			.range([minWidth, maxWidth])(d.score);
	}

	enterLinkLabel(enter: any) {
		const linkLabelSize = this.linkLabelSize * this.dynamicScale;
		return enter.append('text')
			.attr('class', 'smart-connections-visualizer-link-label')
			.attr('font-size', linkLabelSize)
			.attr('fill', '#8AB4F8')
			.attr('opacity', 0)
			.attr('x', (d: any) => (d.source.x + d.target.x) / 2)
			.attr('y', (d: any) => (d.source.y + d.target.y) / 2)
			.text((d: any) => (d.score * 100).toFixed(1) + '%');
	}

	updateLinkLabel(update: any) {
		const linkLabelSize = this.linkLabelSize * this.dynamicScale;
		return update.text((d: any) => (d.score * 100).toFixed(1))
		.attr('x', (d: any) => (d.source.x + d.target.x) / 2)
		.attr('y', (d: any) => (d.source.y + d.target.y) / 2)
		.attr('font-size', linkLabelSize);
	}

	enterLabel(enter: any) {
		const nodeLabelSize = this.nodeLabelSize * this.dynamicScale;
		return enter.append('text')
			.attr('class', 'smart-connections-visualizer-label')
			.attr('dx', 0)
			.attr('font-size', nodeLabelSize)
			.attr('dy', 12)
			.attr('text-anchor', 'middle')
			.attr('fill', '#ccd0d9')
			.attr('data-id', (d: any) => d.id)
			.attr('opacity', 1)
			.attr('x', (d: any) => d.x)
			.attr('y', (d: any) => d.y)
			.text((d: any) => this.formatLabel(d.name));
	}

	updateLabel(update: any) {
		const nodeLabelSize = this.nodeLabelSize * this.dynamicScale;
		return update.attr('dx', 0)
			.attr('data-id', (d: any) => d.id)
			.attr('text-anchor', 'middle')
			.text((d: any) => d.id === this.highlightedNodeId ? this.formatLabel(d.name, false) : this.formatLabel(d.name, true))
			.attr('fill', '#ccd0d9')
			.attr('font-size', nodeLabelSize)
			.attr('x', (d: any) => d.x)
			.attr('y', (d: any) => d.y)
			.attr('opacity', 1);
	}

	updateNodeSizes() {
		this.nodeSelection.attr('r', (d: any) => d.id === this.centralNode.id ? this.nodeSize + 3 : this.nodeSize);
	}

	updateLinkThickness() {
		const minWidth = this.minLinkThickness * this.dynamicScale;
		const maxWidth = this.maxLinkThickness * this.dynamicScale;
		const linkStrokeScale = d3.scaleLinear()
			.domain([this.minScore, this.maxScore])
			.range([minWidth, maxWidth]);
		this.linkSelection.attr('stroke-width', (d: any) => linkStrokeScale(d.score));
	}

	updateSimulationForces() {
		if (!this.simulation) {
			console.error('Simulation not initialized');
			return;
		}
		this.simulation
			.force('charge', d3.forceManyBody().strength(-this.repelForce))
			.force('link', d3.forceLink(this.validatedLinks)
				.id((d: any) => d.id)
				.distance((d: any) => this.linkDistanceScale(d.score))
				.strength(this.linkForce));

    	this.simulation.alphaTarget(0.3).restart();

		setTimeout(() => {
			this.simulation.alphaTarget(0);
		}, 1000);
	}

	normalizeScore(score: number) : number {
		if (this.minScore === this.maxScore) {
			return 0.5;
		}
        return (score - this.minScore) / (this.maxScore - this.minScore);
    }

	linkDistanceScale(score: number) {
        return d3.scaleLinear()
            .domain([0, 1])
            .range([this.linkDistance * 2, this.linkDistance / 2])(this.normalizeScore(score));
    }

	updateLabelOpacity(zoomLevel: number) {
		const maxOpacity = 1;
		const minOpacity = 0;
		const minZoom = 0.1;
		const maxZoom = this.textFadeThreshold;

		let newOpacity = (zoomLevel - minZoom) / (maxZoom - minZoom);
		if (zoomLevel <= minZoom) newOpacity = minOpacity;
		if (zoomLevel >= maxZoom) newOpacity = maxOpacity;

		newOpacity = Math.max(minOpacity, Math.min(maxOpacity, newOpacity));

		if (this.labelSelection) {
			this.labelSelection.transition().duration(300).attr('opacity', newOpacity);
		}
	}

	updateNodeLabels() {
		this.labelSelection.attr('font-size', this.nodeLabelSize)
			.text((d: any) => this.formatLabel(d.name, true));
	}

	updateLinkLabelSizes() {
		if (this.linkLabelSelection) {
			this.linkLabelSelection.attr('font-size', this.linkLabelSize);
		}
	}

	updateNodeLabelSizes() {
		this.labelSelection.attr('font-size', this.nodeLabelSize);
	}

	onunload() {
		if (this.simulation) {
			this.simulation.stop();
			this.simulation = null;
		}
		this.nodeSelection = null;
		this.linkSelection = null;
		this.linkLabelSelection = null;
		this.labelSelection = null;
		this.svgGroup = null;
		this.svg = null;
	}

	updateNodeColors(type: string, color: string) {
		if (type === 'note' && color !== this.noteFillColor) {
			this.noteFillColor = color;
			this.plugin.settings.noteFillColor = color;
			this.plugin.saveSettings();
		}

		if (type === 'block' && color !== this.blockFillColor) {
			this.blockFillColor = color;
			this.plugin.settings.blockFillColor = color;
			this.plugin.saveSettings();
		}

		this.nodes.forEach((node: any) => {
			if (node.group === type) {
				node.fill = color;
			}
		});
		this.updateNodeFill();
	}

	updateNodeFill() {
		this.nodeSelection.attr('fill', (d: any) => d.fill);
	}

	avoidLabelCollisions() {
		const padding = 5;
		return (alpha: number) => {
			const quadtree = d3.quadtree()
				.x((d: any) => d.x)
				.y((d: any) => d.y)
				.addAll(this.labelSelection.data());

			this.labelSelection.each((d: any) => {
				const radius = d.radius + padding;
				const nx1 = d.x - radius, nx2 = d.x + radius, ny1 = d.y - radius, ny2 = d.y + radius;

				quadtree.visit((quad: any, x1: number, y1: number, x2: number, y2: number) => {
					if ('data' in quad && quad.data && (quad.data !== d)) {
						let x = d.x - quad.data.x,
							y = d.y - quad.data.y,
							l = Math.sqrt(x * x + y * y),
							r = radius + quad.data.radius;
						if (l < r) {
							l = (l - r) / l * alpha;
							d.x -= x *= l;
							d.y -= y *= l;
							quad.data.x += x;
							quad.data.y += y;
						}
					}
					return x1 > nx2 || x2 < nx1 || y1 > ny2 || y2 < ny1;
				});
			});
		};
	}
}

export default class ScGraphView extends Plugin {

	settings: PluginSettings;

    async onload() {
		try {
			await this.loadSettings();

			this.registerView("smart-connections-visualizer", (leaf: WorkspaceLeaf) => new ScGraphItemView(leaf, this));

			this.registerHoverLinkSource('smart-connections-visualizer', {
				display: 'Smart connections visualizer hover link source',
				defaultMod: true
			});

			this.addCommand({
				id: 'open-smart-connections-visualizer',
				name: 'Open Smart Connections Visualizer',
				callback: async () => {
					await this.openSmartConnectionsVisualizer();
				}
			});

			this.addRibbonIcon('git-fork', 'Open smart connections visualizer', async (evt: MouseEvent) => {
				await this.openSmartConnectionsVisualizer();
			});

			console.log("Smart Connections Visualizer plugin loaded successfully");
		} catch (error) {
			console.error("Error loading Smart Connections Visualizer plugin:", error);
			new Notice("Failed to load Smart Connections Visualizer plugin. Check console for details.");
		}
    }

	async openSmartConnectionsVisualizer() {
		try {
			const existingLeaf = this.app.workspace.getLeavesOfType("smart-connections-visualizer")[0];
			if (existingLeaf) {
				this.app.workspace.setActiveLeaf(existingLeaf);
			} else {
				let leaf = this.app.workspace.getRightLeaf(false);
				if (!leaf) {
					leaf = this.app.workspace.getLeaf(true);
				}
				await leaf.setViewState({
					type: "smart-connections-visualizer",
					active: true,
				});
			}
		} catch (error) {
			console.error("Error opening Smart Connections Visualizer:", error);
			new Notice("Failed to open Smart Connections Visualizer. Check console for details.");
		}
	}

	async loadSettings() {
        this.settings = Object.assign({}, DEFAULT_NETWORK_SETTINGS, await this.loadData());
    }

	async saveSettings() {
        await this.saveData(this.settings);
    }

    onunload() {
		// Clean up any open views
		const leaves = this.app.workspace.getLeavesOfType("smart-connections-visualizer");
		leaves.forEach(leaf => leaf.detach());
    }
}
