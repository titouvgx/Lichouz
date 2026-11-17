// QR code (v2.1.0) : calculé sur le téléphone avec qrcode-generator (MIT, sans dépendance),
// aucun service extérieur. On ne garde que le tracé : un seul <path> SVG, sans innerHTML.
import qrcode from 'qrcode-generator'

export interface QrDrawing {
  /** Nombre de modules par côté (sans la marge). */
  size: number
  /** Tracé SVG des modules sombres, en unités de module. */
  path: string
}

/** Correction « M » : lisible même un peu abîmé, assez petit pour un lien. */
export function qrDrawing(text: string): QrDrawing {
  const qr = qrcode(0, 'M')
  qr.addData(text, 'Byte')
  qr.make()
  const size = qr.getModuleCount()
  let path = ''
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      if (qr.isDark(r, c)) path += `M${c} ${r}h1v1h-1z`
    }
  }
  return { size, path }
}
