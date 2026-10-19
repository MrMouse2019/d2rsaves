using D2SSharp.Data;
using D2SSharp.Enums;
using D2SSharp.IO;

namespace D2SSharp.Model;

/// <summary>
/// Player stats section (variable length, bit-packed).
/// </summary>
public partial class PlayerStats : List<Stat>
{
    /// <summary>Section magic: "gf" (0x6667)</summary>
    public const ushort Magic = 0x6667;

    /// <summary>
    /// Gets a stat value by ID.
    /// </summary>
    public long GetStat(StatId statId)
    {
        var stat = this.FirstOrDefault(s => s.Id == statId);
        return stat?.Id == statId ? stat.Value : 0;
    }

    /// <summary>
    /// Sets a stat value by ID.
    /// </summary>
    public void SetStat(StatId statId, long value, int layer = 0)
    {
        var index = FindIndex(s => s.Id == statId);
        if (index >= 0)
        {
            this[index] = new Stat { Id = statId, Layer = layer, Value = value };
        }
        else
        {
            Add(new Stat { Id = statId, Layer = layer, Value = value });
        }
    }

    /// <summary>
    /// Reads a player stats section from a BitReader.
    /// </summary>
    public static PlayerStats Read(ref BitReader reader, IExternalData externalData, uint saveVersion)
    {
        var stats = new PlayerStats();

        // Verify magic "gf"
        ushort magic = reader.ReadUInt16();
        if (magic != Magic)
            throw new InvalidDataException($"Invalid stats section magic: 0x{magic:X4}");

        // Read stats until terminator
        while (true)
        {
            StatId statId = (StatId)reader.ReadBits(9);

            if (statId == StatId.Terminator)
                break;

            var statInfo = externalData.GetStatInfo(statId, saveVersion);

            // C++ reads layer as signed (BITMANIP_ReadSigned)
            int layer = 0;
            if (statInfo.CsvParam > 0)
            {
                layer = reader.ReadSignedBits(statInfo.CsvParam);
            }

            // C++ only uses signed read if CsvBits < 32 AND CsvSigned flag is set
            long value;
            if (statInfo.CsvBits < 32 && statInfo.CsvSigned)
            {
                value = reader.ReadSignedBits(statInfo.CsvBits);
            }
            else
            {
                value = reader.ReadBits(statInfo.CsvBits);
            }

            stats.Add(new Stat { Id = statId, Layer = layer, Value = value });
        }

        // Align to byte boundary after reading stats
        reader.AlignToByte();

        return stats;
    }

    /// <summary>
    /// Writes a player stats section to a BitWriter.
    /// </summary>
    public void Write(ref BitWriter writer, IExternalData externalData, uint saveVersion)
    {
        // Write magic "gf"
        writer.WriteUInt16(Magic);

        // Write each stat
        foreach (var stat in this)
        {
            var statInfo = externalData.GetStatInfo(stat.Id, saveVersion);

            // Clamp value to valid range (matching C++ PLRSAVE2_WritePlayerStats)
            long value = stat.Value;
            int csvBits = statInfo.CsvBits;

            if (csvBits < 32)
            {
                if (statInfo.CsvSigned)
                {
                    // Signed: range is [-(1 << (bits-1)), (1 << (bits-1)) - 1]
                    long min = -(1L << (csvBits - 1));
                    long max = (1L << (csvBits - 1)) - 1;
                    value = Math.Clamp(value, min, max);
                }
                else
                {
                    // Unsigned: range is [0, (1 << bits) - 1]
                    long max = (1L << csvBits) - 1;
                    value = Math.Clamp(value, 0, max);
                }
            }

            writer.WriteBits((uint)stat.Id, 9);

            // C++ writes layer as unsigned (but reads as signed - two's complement)
            if (statInfo.CsvParam > 0)
            {
                writer.WriteBits((uint)stat.Layer, statInfo.CsvParam);
            }

            // C++ only uses signed handling if CsvBits < 32 AND CsvSigned flag is set
            if (csvBits < 32 && statInfo.CsvSigned)
            {
                writer.WriteSignedBits((int)value, csvBits);
            }
            else
            {
                writer.WriteBits((uint)value, csvBits);
            }
        }

        // Write terminator
        writer.WriteBits((uint)StatId.Terminator, 9);

        // Align to byte boundary
        writer.AlignToByte();
    }
}
