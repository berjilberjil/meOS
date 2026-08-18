// Downscale + compress images before upload so they load fast everywhere.
// Keeps the original if it's already small or compression doesn't help.
export async function compressImage(file: File, maxDim = 1600, quality = 0.82): Promise<File> {
	if (typeof document === 'undefined') return file;
	if (!file.type.startsWith('image/') || file.type === 'image/gif') return file;
	try {
		const bitmap = await createImageBitmap(file);
		let { width, height } = bitmap;
		const longest = Math.max(width, height);
		if (longest > maxDim) {
			const s = maxDim / longest;
			width = Math.round(width * s);
			height = Math.round(height * s);
		}
		const canvas = document.createElement('canvas');
		canvas.width = width;
		canvas.height = height;
		const ctx = canvas.getContext('2d');
		if (!ctx) return file;
		ctx.drawImage(bitmap, 0, 0, width, height);
		bitmap.close?.();
		const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, 'image/jpeg', quality));
		if (!blob || blob.size >= file.size) return file;
		const name = file.name.replace(/\.\w+$/, '') + '.jpg';
		return new File([blob], name, { type: 'image/jpeg' });
	} catch {
		return file;
	}
}
