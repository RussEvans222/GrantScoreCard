/*
This class is the low-level Prompt Builder connector.
It takes plain Apex input values, wraps them in the ConnectApi format,
calls the prompt template, and returns the first text generation.

Why this exists:
- Keeps AI call details in one place.
- Makes service classes simpler and easier to read.
*/
/*
AI PROMPT INTEGRATION NOTES

This invoker is shared infrastructure for Prompt Builder templates.
Current examples in GrantScoreCard include:
- EvaluationFrameworkReview
- ETDisplayName

When a service needs AI output, it prepares record-based inputs,
calls this invoker, and receives generated text for parsing or storage.
*/
public with sharing class EvaluationFrameworkPromptInvoker {
    public static String invokeTemplate(String templateApiName, Map<String, Object> inputParams) {
        // Prompt Builder expects each input in a WrappedValue object.
        Map<String, ConnectApi.WrappedValue> wrappedInputParams = new Map<String, ConnectApi.WrappedValue>();
        for (String key : inputParams.keySet()) {
            ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
            wrapped.value = inputParams.get(key);
            wrappedInputParams.put(key, wrapped);
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput generationInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        generationInput.inputParams = wrappedInputParams;
        generationInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        generationInput.additionalConfig.applicationName = 'PromptBuilderPreview';
        generationInput.isPreview = false;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateApiName, generationInput);

        // Defensive checks protect callers from null/empty AI responses.
        if (generationOutput == null || generationOutput.generations == null || generationOutput.generations.isEmpty()) {
            throw new AuraHandledException('Prompt did not return any generations.');
        }

        ConnectApi.EinsteinLLMGenerationItemOutput firstGeneration = generationOutput.generations[0];
        if (firstGeneration == null || String.isBlank(firstGeneration.text)) {
            throw new AuraHandledException('Prompt returned an empty generation payload.');
        }
        return firstGeneration.text;
    }
}