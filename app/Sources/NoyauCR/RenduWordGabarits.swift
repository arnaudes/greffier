import Foundation

/// Les pièces fixes d'un document Word.
///
/// Un `.docx` n'est pas un fichier mais une petite arborescence : la liste de
/// ses types, ses relations, ses styles, sa numérotation, son pied de page. Ce
/// qui suit ne change jamais d'un compte rendu à l'autre — hormis les couleurs,
/// qui viennent de la charte.
extension RenduWord {

    var espacesDeNoms: String {
        #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""#
    }

    var typesDeContenu: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
        </Types>
        """
    }

    var relationsRacine: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    var relationsDocument: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
        </Relationships>
        """
    }

    /// Les styles nommés. C'est ce qui distingue un vrai document Word d'une
    /// mise en forme plaquée : le volet de navigation s'appuie dessus, et le
    /// destinataire peut reprendre la charte à sa main sans tout resaisir.
    var styles: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles \(espacesDeNoms)>
        <w:docDefaults><w:rPrDefault><w:rPr>\(fonte)\
        <w:color w:val="\(charte.encre)"/><w:sz w:val="\(demiPoints)"/></w:rPr></w:rPrDefault>
        <w:pPrDefault><w:pPr><w:spacing w:after="180" w:line="288" w:lineRule="auto"/>\
        </w:pPr></w:pPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>
        <w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
        <w:pPr><w:keepNext/><w:outlineLvl w:val="0"/></w:pPr>
        <w:rPr><w:b/><w:color w:val="\(charte.encreForte)"/><w:sz w:val="32"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>
        <w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
        <w:pPr><w:keepNext/><w:spacing w:before="260" w:after="120"/>\
        <w:outlineLvl w:val="1"/></w:pPr>
        <w:rPr><w:b/><w:color w:val="\(charte.encreForte)"/><w:sz w:val="24"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:styleId="ListePuces"><w:name w:val="List Bullet"/>
        <w:basedOn w:val="Normal"/><w:qFormat/>
        <w:pPr><w:spacing w:after="60"/><w:ind w:left="360" w:hanging="360"/></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="ListeNumerotee"><w:name w:val="List Number"/>
        <w:basedOn w:val="Normal"/><w:qFormat/>
        <w:pPr><w:spacing w:after="60"/><w:ind w:left="360" w:hanging="360"/></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="Pied"><w:name w:val="footer"/>
        <w:basedOn w:val="Normal"/>
        <w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr>
        <w:rPr><w:color w:val="\(charte.encreFaible)"/><w:sz w:val="17"/></w:rPr></w:style>
        </w:styles>
        """
    }

    /// Les puces et la numérotation. Sans cette pièce, Word affiche des
    /// paragraphes indentés là où le compte rendu énumère.
    var numerotation: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering \(espacesDeNoms)>
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>
        <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
        <w:lvlText w:val="•"/><w:lvlJc w:val="left"/>
        <w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr>
        <w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:hint="default"/>\
        <w:color w:val="\(charte.accent)"/></w:rPr></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>
        <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>
        <w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>
        <w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr>
        <w:rPr><w:b/><w:color w:val="\(charte.accent)"/></w:rPr></w:lvl></w:abstractNum>
        <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
        <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
        </w:numbering>
        """
    }

    /// « Page 3 / 12 », au bas de chaque page. Un compte rendu qu'on imprime
    /// et qui perd une feuille sans que personne s'en aperçoive n'est plus un
    /// document de référence.
    var piedDePage: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:ftr \(espacesDeNoms)>
        <w:p><w:pPr><w:pStyle w:val="Pied"/></w:pPr>
        <w:r><w:rPr>\(fonte)<w:color w:val="\(charte.encreFaible)"/>\
        <w:sz w:val="17"/></w:rPr><w:t xml:space="preserve">Page </w:t></w:r>
        <w:r><w:fldChar w:fldCharType="begin"/></w:r>
        <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
        <w:r><w:fldChar w:fldCharType="separate"/></w:r>
        <w:r><w:fldChar w:fldCharType="end"/></w:r>
        <w:r><w:rPr>\(fonte)<w:color w:val="\(charte.encreFaible)"/>\
        <w:sz w:val="17"/></w:rPr><w:t xml:space="preserve"> / </w:t></w:r>
        <w:r><w:fldChar w:fldCharType="begin"/></w:r>
        <w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>
        <w:r><w:fldChar w:fldCharType="separate"/></w:r>
        <w:r><w:fldChar w:fldCharType="end"/></w:r>
        </w:p></w:ftr>
        """
    }

    /// Le format de la page : A4, marges confortables, et le pied rattaché.
    var finDeSection: String {
        """
        <w:sectPr><w:footerReference w:type="default" r:id="rId3" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>\
        <w:pgSz w:w="11906" w:h="16838"/>\
        <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" \
        w:header="567" w:footer="567" w:gutter="0"/></w:sectPr>
        """
    }

    /// Les bordures d'un tableau de données : un filet fin, rien de plus.
    var bordureTableau: String {
        let f = charte.filet
        return "<w:top w:val=\"single\" w:sz=\"4\" w:color=\"\(f)\"/>"
            + "<w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"\(f)\"/>"
            + "<w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"\(f)\"/>"
            + "<w:left w:val=\"nil\"/><w:right w:val=\"nil\"/><w:insideV w:val=\"nil\"/>"
    }

    /// Une fiche d'identité ne s'encadre pas : elle se lit comme un en-tête.
    var bordureFiche: String {
        "<w:top w:val=\"nil\"/><w:bottom w:val=\"nil\"/><w:left w:val=\"nil\"/>"
            + "<w:right w:val=\"nil\"/><w:insideH w:val=\"nil\"/><w:insideV w:val=\"nil\"/>"
    }

    var bordureNulle: String { bordureFiche }
}
