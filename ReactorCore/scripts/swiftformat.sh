#! /bin/sh

function assertEnvironment {
	if [ -z $1 ]; then 
		echo $2
		exit 127
	fi
}

assertEnvironment "${PODS_ROOT}" "Please set PODS_ROOT to root pods folder"
assertEnvironment "${SRCROOT}" "Please set SRCROOT to project root folder"

"${PODS_ROOT}/SwiftFormat/CommandLineTool/swiftformat" "${SRCROOT}" \
--enable blankLinesAroundMark,\
blankLinesAtEndOfScope,\
blankLinesAtStartOfScope,\
blankLinesBetweenScopes,\
consecutiveBlankLines,\
consecutiveSpaces,\
duplicateImports,\
elseOnSameLine,\
fileHeader,\
hoistPatternLet,\
indent,\
linebreakAtEndOfFile,\
linebreaks,\
numberFormatting,\
ranges,\
redundantBackticks,\
redundantGet,\
redundantInit,\
redundantLet,\
redundantNilInit,\
redundantParens,\
redundantPattern,\
redundantRawValues,\
redundantReturn,\
redundantSelf,\
redundantVoidReturnType,\
semicolons,\
sortedImports,\
spaceAroundBraces,\
spaceAroundBrackets,\
spaceAroundComments,\
spaceAroundGenerics,\
spaceAroundOperators,\
spaceAroundParens,\
spaceInsideBraces,\
spaceInsideBrackets,\
spaceInsideComments,\
spaceInsideGenerics,\
spaceInsideParens,\
specifiers,\
strongOutlets,\
todos,\
trailingCommas,\
trailingSpace,\
unusedArguments,\
void,\
wrapArguments \
--disable braces,\
trailingClosures \
--header strip \
--commas inline \
--comments indent \
--ifdef indent \
--indent 4 \
--hexliteralcase uppercase \
--exponentcase uppercase \
--hexgrouping 4,8 \
--binarygrouping 4,8 \
--decimalgrouping 3,6 \
--octalgrouping 4,8 \
--ranges spaced \
--self remove \
--semicolons never \
--trimwhitespace always \
--wraparguments preserve \
--wrapcollections beforefirst \
--exclude R.generated.swift
