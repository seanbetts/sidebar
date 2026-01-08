import {
	FileChartPie,
	FileText,
	FileSpreadsheet,
	FileMusic,
	FileVideoCamera,
	FileChartLine,
	Image
} from 'lucide-svelte';

export const categoryOrder = [
	'audio',
	'documents',
	'images',
	'presentations',
	'reports',
	'spreadsheets',
	'video',
	'other'
];

export const categoryLabels: Record<string, string> = {
	images: 'Images',
	documents: 'Documents',
	spreadsheets: 'Spreadsheets',
	presentations: 'Presentations',
	reports: 'Reports',
	audio: 'Audio',
	video: 'Video',
	other: 'Other'
};

export function iconForCategory(category: string | null | undefined) {
	if (category === 'images') return Image;
	if (category === 'spreadsheets') return FileSpreadsheet;
	if (category === 'presentations') return FileChartPie;
	if (category === 'reports') return FileChartLine;
	if (category === 'audio') return FileMusic;
	if (category === 'video') return FileVideoCamera;
	return FileText;
}

export function stripExtension(name: string): string {
	const index = name.lastIndexOf('.');
	if (index <= 0) return name;
	return name.slice(0, index);
}
