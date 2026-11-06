import fs from "node:fs/promises";

// Бит `track_in_preview` (0x4) в флагах заголовка трека (tkhd). Инстаграм ставит флаги 0x7 (включён, в фильме, в предпросмотре);
// с этим битом плеер Windows рисует у вертикальных видео полосу справа. Те же файлы с флагами 0x3 играют чисто, а сам бит
// ни на что, кроме предпросмотра QuickTime, не влияет. Меняем один байт на трек прямо в файле — поток и размеры не трогаем.
const TRACK_IN_PREVIEW = 0x04;
const MAX_MOOV_BYTES = 64 * 1024 * 1024;

/** Позиции байтов флагов tkhd (младший байт), у которых выставлен бит предпросмотра, внутри буфера moov. */
function previewFlagPositions(moov) {
  const positions = [];
  const children = (start, end, onBox) => {
    let i = start;
    while (i + 8 <= end) {
      const size = moov.readUInt32BE(i);
      const type = moov.toString("latin1", i + 4, i + 8);
      if (size < 8 || i + size > end) break;
      onBox(type, i, size);
      i += size;
    }
  };
  children(8, moov.length, (type, offset, size) => {
    if (type !== "trak") return;
    children(offset + 8, offset + size, (inner, innerOffset, innerSize) => {
      if (inner !== "tkhd" || innerSize < 12) return;
      const flagsLowByte = innerOffset + 8 + 3; // заголовок бокса (8) + версия (1) + старшие байты флагов (2)
      if (moov[flagsLowByte] & TRACK_IN_PREVIEW) positions.push(flagsLowByte);
    });
  });
  return positions;
}

/**
 * Сбрасывает бит предпросмотра у всех треков MP4-файла (на месте). Возвращает число изменённых треков;
 * файл без moov или с неожиданной структурой не меняется.
 */
async function clearTrackPreviewFlag(filePath) {
  const handle = await fs.open(filePath, "r+");
  try {
    const { size: fileSize } = await handle.stat();
    const header = Buffer.alloc(16);
    let offset = 0;
    while (offset + 8 <= fileSize) {
      const { bytesRead } = await handle.read(header, 0, 16, offset);
      if (bytesRead < 8) return 0;
      let boxSize = header.readUInt32BE(0);
      const type = header.toString("latin1", 4, 8);
      if (boxSize === 1) {
        if (bytesRead < 16) return 0;
        boxSize = Number(header.readBigUInt64BE(8));
      } else if (boxSize === 0) {
        boxSize = fileSize - offset;
      }
      if (boxSize < 8 || offset + boxSize > fileSize) return 0;
      if (type === "moov") {
        if (boxSize > MAX_MOOV_BYTES) return 0;
        const moov = Buffer.alloc(boxSize);
        await handle.read(moov, 0, boxSize, offset);
        const positions = previewFlagPositions(moov);
        for (const position of positions) {
          await handle.write(Buffer.from([moov[position] & ~TRACK_IN_PREVIEW]), 0, 1, offset + position);
        }
        return positions.length;
      }
      offset += boxSize;
    }
    return 0;
  } finally {
    await handle.close();
  }
}

export { clearTrackPreviewFlag, previewFlagPositions };
