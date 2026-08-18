// Global image viewer: any thumbnail can open a zoomable full-screen view.
export const lightbox = $state<{ url: string; alt: string }>({ url: '', alt: '' });

export function openLightbox(url: string, alt = ''): void {
	lightbox.url = url;
	lightbox.alt = alt;
}
export function closeLightbox(): void {
	lightbox.url = '';
}
