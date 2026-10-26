import { ref, computed } from 'vue';
import { AsYouType, isValidPhoneNumber } from 'libphonenumber-js';

export const BRAZIL_DIAL_CODE = '+55';
const BRAZIL_REGION = 'BR';
// Area code plus a 9-digit mobile number
const BRAZIL_NUMBER_DIGITS = 11;
const AREA_CODE_DIGITS = 2;

/**
 * A Brazilian phone number typed without the +55: keeps only the digits, masks them as
 * they are typed, e.g. (81) 99667-4379, and gives the E.164 number to send.
 */
export function useBrazilianPhoneNumber() {
  const digits = ref('');

  // The area code gets its parentheses only once the number starts, so backspace never stops at ")"
  const formatted = computed(() =>
    digits.value.length > AREA_CODE_DIGITS
      ? new AsYouType(BRAZIL_REGION).input(digits.value)
      : digits.value
  );
  const e164 = computed(() => `${BRAZIL_DIAL_CODE}${digits.value}`);
  const isValid = computed(() =>
    isValidPhoneNumber(digits.value, BRAZIL_REGION)
  );

  const onInput = event => {
    const input = event.target;
    const digitsBeforeCaret = input.value
      .slice(0, input.selectionStart)
      .replace(/\D/g, '').length;
    digits.value = input.value
      .replace(/\D/g, '')
      .slice(0, BRAZIL_NUMBER_DIGITS);
    input.value = formatted.value;

    // Rewriting the value moves the caret to the end; put it back after the same digit
    let caret = 0;
    for (
      let seen = 0;
      caret < input.value.length && seen < digitsBeforeCaret;
      caret += 1
    ) {
      if (/\d/.test(input.value[caret])) seen += 1;
    }
    input.setSelectionRange(caret, caret);
  };

  return { digits, formatted, e164, isValid, onInput };
}
