using D2SSharp.Enums;
using D2SSharp.IO;

namespace D2SSharp.Model;

/// <summary>
/// Quest data section (298 bytes).
/// </summary>
public partial class QuestSection
{
    /// <summary>Section magic: "Woo!" (0x216F6F57)</summary>
    public const uint Magic = 0x216F6F57;

    /// <summary>Section size in bytes.</summary>
    public const int Size = 298;

    /// <summary>Quest section version (always 6).</summary>
    public const uint CurrentVersion = 6;

    /// <summary>Quest section version.</summary>
    public uint Version { get; set; } = CurrentVersion;

    /// <summary>Section size field (always 298).</summary>
    public ushort SectionSize { get; set; } = Size;

    /// <summary>Quest data for Normal difficulty.</summary>
    public QuestsDifficulty Normal { get; set; } = new();

    /// <summary>Quest data for Nightmare difficulty.</summary>
    public QuestsDifficulty Nightmare { get; set; } = new();

    /// <summary>Quest data for Hell difficulty.</summary>
    public QuestsDifficulty Hell { get; set; } = new();

    /// <summary>
    /// Gets quest data for a specific difficulty.
    /// </summary>
    public QuestsDifficulty GetQuests(Difficulty difficulty) => difficulty switch
    {
        Difficulty.Normal => Normal,
        Difficulty.Nightmare => Nightmare,
        Difficulty.Hell => Hell,
        _ => throw new ArgumentOutOfRangeException(nameof(difficulty))
    };

    /// <summary>
    /// Reads a quest section from a BitReader.
    /// </summary>
    public static QuestSection Read(ref BitReader reader)
    {
        var section = new QuestSection();

        // Verify magic "Woo!"
        uint magic = reader.ReadUInt32();
        if (magic != Magic)
            throw new InvalidDataException($"Invalid quest section magic: 0x{magic:X8}");

        section.Version = reader.ReadUInt32();
        section.SectionSize = reader.ReadUInt16();

        section.Normal = QuestsDifficulty.Read(ref reader);
        section.Nightmare = QuestsDifficulty.Read(ref reader);
        section.Hell = QuestsDifficulty.Read(ref reader);

        return section;
    }

    /// <summary>
    /// Writes a quest section to a BitWriter.
    /// </summary>
    public void Write(ref BitWriter writer)
    {
        // Write magic "Woo!"
        writer.WriteUInt32(Magic);

        writer.WriteUInt32(Version);
        writer.WriteUInt16(SectionSize);

        Normal.Write(ref writer);
        Nightmare.Write(ref writer);
        Hell.Write(ref writer);
    }
}
