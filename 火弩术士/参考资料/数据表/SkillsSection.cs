using D2SSharp.Enums;
using D2SSharp.IO;

namespace D2SSharp.Model;

/// <summary>
/// Skills section (variable length based on class).
/// </summary>
public partial class SkillsSection
{
    /// <summary>Section magic: "if" (0x6669)</summary>
    public const ushort Magic = 0x6669;

    /// <summary>Number of skills per class.</summary>
    public const int SkillsPerClass = 30;

    /// <summary>
    /// Base skill ID offsets for each class.
    /// Skills are stored sequentially in the save file, and this maps the index to actual skill ID.
    /// </summary>
    public static readonly int[] ClassSkillOffsets =
    [
        6,    // Amazon
        36,   // Sorceress
        66,   // Necromancer
        96,   // Paladin
        126,  // Barbarian
        221,  // Druid
        251,  // Assassin
        373   // Warlock
    ];

    /// <summary>The character class this skills section belongs to.</summary>
    public CharacterClass CharacterClass { get; set; }

    /// <summary>Skill levels (one byte per skill, indexed by skill offset within class).</summary>
    public byte[] SkillLevels { get; set; } = [];

    /// <summary>
    /// Gets the base skill ID offset for this character's class.
    /// </summary>
    public int SkillIdOffset => ClassSkillOffsets[(int)CharacterClass];

    /// <summary>
    /// Gets the level of a skill at the given index (0-29 within class).
    /// </summary>
    public int this[int index]
    {
        get => index >= 0 && index < SkillLevels.Length ? SkillLevels[index] : 0;
        set
        {
            if (index >= 0 && index < SkillLevels.Length)
                SkillLevels[index] = (byte)Math.Clamp(value, 0, 255);
        }
    }

    /// <summary>
    /// Gets the actual skill ID for an index (0-29).
    /// </summary>
    public int GetSkillId(int index)
    {
        if (index < 0 || index >= SkillsPerClass)
            return -1;
        return SkillIdOffset + index;
    }

    /// <summary>
    /// Gets the index (0-29) for a skill ID.
    /// Returns -1 if the skill doesn't belong to this class.
    /// </summary>
    public int GetSkillIndex(int skillId)
    {
        int index = skillId - SkillIdOffset;
        return index >= 0 && index < SkillsPerClass ? index : -1;
    }

    /// <summary>
    /// Reads a skills section from a BitReader.
    /// </summary>
    public static SkillsSection Read(ref BitReader reader, CharacterClass characterClass, int skillCount)
    {
        var section = new SkillsSection { CharacterClass = characterClass };

        // Verify magic "if"
        ushort magic = reader.ReadUInt16();
        if (magic != Magic)
            throw new InvalidDataException($"Invalid skills section magic: 0x{magic:X4}");

        section.SkillLevels = new byte[skillCount];
        reader.ReadBytes(section.SkillLevels);

        return section;
    }

    /// <summary>
    /// Writes a skills section to a BitWriter.
    /// </summary>
    public void Write(ref BitWriter writer)
    {
        // Write magic "if"
        writer.WriteUInt16(Magic);

        writer.WriteBytes(SkillLevels);
    }
}
